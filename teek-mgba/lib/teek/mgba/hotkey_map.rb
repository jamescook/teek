# frozen_string_literal: true

require 'set'

module Teek
  module MGBA
    # Maps player actions (quit, pause, etc.) to keyboard hotkeys.
    #
    # A hotkey is either a plain keysym String ("F5") or an Array of
    # modifier(s) + key (["Control", "s"]). Provides reverse lookup for
    # efficient dispatch in the input loop.
    class HotkeyMap
      ACTIONS = %i[quit pause fast_forward fullscreen show_fps
                   quick_save quick_load save_states screenshot rewind
                   record].freeze

      DEFAULTS = {
        quit: 'q', pause: 'p', fast_forward: 'Tab',
        fullscreen: 'F11', show_fps: 'F3',
        quick_save: 'F5', quick_load: 'F8',
        save_states: 'F6', screenshot: 'F9',
        rewind: ['Shift', 'Tab'],
        record: 'F10',
      }.freeze

      # Tk keysyms that are modifier keys → normalized name
      MODIFIER_KEYSYMS = {
        'Control_L' => 'Control', 'Control_R' => 'Control',
        'Shift_L' => 'Shift', 'Shift_R' => 'Shift',
        'Alt_L' => 'Alt', 'Alt_R' => 'Alt',
        'Meta_L' => 'Alt', 'Meta_R' => 'Alt',
        'Super_L' => 'Super', 'Super_R' => 'Super',
      }.freeze

      # Tk event state bitmask → modifier name
      STATE_BITS = { 1 => 'Shift', 4 => 'Control', 8 => 'Alt' }.freeze

      # Display-friendly modifier names
      MODIFIER_DISPLAY = { 'Control' => 'Ctrl', 'Shift' => 'Shift', 'Alt' => 'Alt', 'Super' => 'Super' }.freeze

      # Canonical sort order for modifiers
      MODIFIER_ORDER = %w[Control Shift Alt Super].freeze

      # Tk keysym aliases — modifier combos can produce variant keysyms
      # that must be normalized for both lookup and capture.
      #
      # Known cases:
      #   Shift+Tab   → ISO_Left_Tab
      #   Shift+1     → exclam (US layout)
      #   Shift+a     → A (universal — handled dynamically in normalize_keysym)
      KEYSYM_ALIASES = {
        'ISO_Left_Tab' => 'Tab',
        # Shift+number (US keyboard layout)
        'exclam'       => '1', 'at'           => '2', 'numbersign'   => '3',
        'dollar'       => '4', 'percent'      => '5', 'asciicircum'  => '6',
        'ampersand'    => '7', 'asterisk'     => '8', 'parenleft'    => '9',
        'parenright'   => '0',
        # Shift+punctuation (US keyboard layout)
        'underscore'   => 'minus',        'plus'         => 'equal',
        'braceleft'    => 'bracketleft',  'braceright'   => 'bracketright',
        'bar'          => 'backslash',    'colon'        => 'semicolon',
        'quotedbl'     => 'apostrophe',   'less'         => 'comma',
        'greater'      => 'period',       'question'     => 'slash',
        'asciitilde'   => 'grave',
      }.freeze

      def initialize(config)
        @config = config
        @map = DEFAULTS.dup
        load_config
      end

      # @param action [Symbol] e.g. :quit, :pause
      # @return [String, Array] hotkey for this action
      def key_for(action)
        @map[action]
      end

      # Look up which action matches a keysym + active modifiers.
      # @param keysym [String] e.g. 'q', 'F5'
      # @param modifiers [Set<String>, nil] active modifier names (e.g. Set["Control"])
      # @return [Symbol, nil] action bound to this hotkey, or nil
      def action_for(keysym, modifiers: nil)
        keysym = self.class.normalize_keysym(keysym)
        mods = modifiers && !modifiers.empty? ? modifiers : nil

        @map.each do |action, hk|
          if hk.is_a?(Array)
            hk_mods = hk[0...-1]
            hk_key = hk.last
            next unless mods && hk_key == keysym
            next unless hk_mods.size == mods.size && hk_mods.all? { |m| mods.include?(m) }
            return action
          else
            return action if hk == keysym && mods.nil?
          end
        end
        nil
      end

      # Rebind an action to a new hotkey. Clears any existing action
      # using the same hotkey to prevent conflicts.
      # @param action [Symbol]
      # @param hotkey [String, Array]
      def set(action, hotkey)
        normalized = self.class.normalize(hotkey)
        @map.delete_if { |_, v| self.class.normalize(v) == normalized }
        @map[action] = normalized
      end

      # Restore all bindings to defaults.
      def reset!
        @map = DEFAULTS.dup
      end

      # Load hotkeys from config. Falls back to defaults for missing keys.
      def load_config
        cfg = @config.hotkeys
        return if cfg.empty?

        @map = DEFAULTS.dup
        cfg.each do |action_str, hk|
          action = action_str.to_sym
          @map[action] = self.class.normalize(hk) if ACTIONS.include?(action)
        end
      end

      # Re-read config from disk, then reload bindings.
      def reload!
        @config.reload!
        load_config
      end

      # Write current hotkeys to config (does not call save!).
      def save_to_config
        @map.each do |action, hk|
          @config.set_hotkey(action, hk)
        end
      end

      # @return [Hash{Symbol => String, Array}] action → raw hotkey
      def labels
        @map.dup
      end

      # Normalize a hotkey: sort modifiers canonically.
      # @param hotkey [String, Array] e.g. "F5" or ["Shift", "Control", "s"]
      # @return [String, Array]
      def self.normalize(hotkey)
        return hotkey unless hotkey.is_a?(Array)
        return hotkey.last if hotkey.size == 1

        key = hotkey.last
        mods = hotkey[0...-1].sort_by { |m| MODIFIER_ORDER.index(m) || 99 }
        [*mods, key]
      end

      # Human-readable display name for a hotkey.
      # @param hotkey [String, Array]
      # @return [String] e.g. "F5", "Ctrl+S"
      def self.display_name(hotkey)
        return hotkey unless hotkey.is_a?(Array)

        parts = hotkey[0...-1].map { |m| MODIFIER_DISPLAY[m] || m }
        parts << hotkey.last.capitalize
        parts.join('+')
      end

      # Normalize variant Tk keysyms to their canonical form.
      # Handles: ISO_Left_Tab → Tab, Shift+letter uppercase → lowercase,
      # Shift+number → number (US layout), Shift+punctuation → base key.
      # @param keysym [String] e.g. 'ISO_Left_Tab', 'Q'
      # @return [String] canonical keysym e.g. 'Tab', 'q'
      def self.normalize_keysym(keysym)
        return KEYSYM_ALIASES[keysym] if KEYSYM_ALIASES.key?(keysym)
        # Shift+letter: single uppercase ASCII letter → lowercase
        return keysym.downcase if keysym.length == 1 && keysym.match?(/\A[A-Z]\z/)
        keysym
      end

      # @param keysym [String] Tk keysym
      # @return [Boolean] true if the keysym is a modifier key
      def self.modifier_key?(keysym)
        MODIFIER_KEYSYMS.key?(keysym)
      end

      # Normalize a Tk modifier keysym (e.g. "Control_L" → "Control").
      # @param keysym [String]
      # @return [String, nil] normalized modifier name, or nil if not a modifier
      def self.normalize_modifier(keysym)
        MODIFIER_KEYSYMS[keysym]
      end

      # Extract active modifier names from a Tk event state bitmask.
      # @param state [Integer] Tk %s value
      # @return [Set<String>]
      def self.modifiers_from_state(state)
        result = Set.new
        STATE_BITS.each { |bit, name| result << name if (state & bit) != 0 }
        result
      end
    end
  end
end
