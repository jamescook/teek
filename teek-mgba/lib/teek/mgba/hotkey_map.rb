# frozen_string_literal: true

module Teek
  module MGBA
    # Maps player actions (quit, pause, etc.) to keyboard keysyms.
    # Provides reverse lookup for efficient dispatch in the input loop.
    class HotkeyMap
      ACTIONS = %i[quit pause fast_forward fullscreen show_fps
                   quick_save quick_load save_states screenshot].freeze

      DEFAULTS = {
        quit: 'q', pause: 'p', fast_forward: 'Tab',
        fullscreen: 'F11', show_fps: 'F3',
        quick_save: 'F5', quick_load: 'F8',
        save_states: 'F6', screenshot: 'F9',
      }.freeze

      def initialize(config)
        @config = config
        @map = DEFAULTS.dup
        load_config
      end

      # @param action [Symbol] e.g. :quit, :pause
      # @return [String] keysym bound to this action
      def key_for(action)
        @map[action]
      end

      # @param keysym [String] e.g. 'q', 'F5'
      # @return [Symbol, nil] action bound to this keysym, or nil
      def action_for(keysym)
        @map.key(keysym)
      end

      # Rebind an action to a new keysym. Clears any existing action
      # using the same keysym to prevent conflicts.
      # @param action [Symbol]
      # @param keysym [String]
      def set(action, keysym)
        @map.delete_if { |_, v| v == keysym }
        @map[action] = keysym
      end

      # Restore all bindings to defaults.
      def reset!
        @map = DEFAULTS.dup
      end

      # Load bindings from config. Falls back to defaults for missing keys.
      def load_config
        cfg = @config.hotkeys
        return if cfg.empty?

        @map = DEFAULTS.dup
        cfg.each do |action_str, keysym|
          action = action_str.to_sym
          @map[action] = keysym if ACTIONS.include?(action)
        end
      end

      # Re-read config from disk, then reload bindings.
      def reload!
        @config.reload!
        load_config
      end

      # Write current bindings to config (does not call save!).
      def save_to_config
        @map.each do |action, keysym|
          @config.set_hotkey(action, keysym)
        end
      end

      # @return [Hash{Symbol => String}] action → keysym for UI display
      def labels
        @map.dup
      end
    end
  end
end
