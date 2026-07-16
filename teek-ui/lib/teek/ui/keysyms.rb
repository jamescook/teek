# frozen_string_literal: true

module Teek
  module UI
    # Translates the DSL's Tk-free key vocabulary (friendly symbols, "Ctrl-x"
    # style modifier strings) into real Tk bind event patterns. Its own small
    # lookup, kept separate from Handle so it's easy to extend.
    module Keysyms
      # Friendly name -> Tk keysym. Anything not listed here passes through
      # as the literal keysym (so e.g. :q or "q" still works for plain letter
      # keys without needing an entry).
      FRIENDLY = {
        enter: 'Return', return: 'Return', escape: 'Escape', tab: 'Tab',
        space: 'space', backspace: 'BackSpace', delete: 'Delete', insert: 'Insert',
        up: 'Up', down: 'Down', left: 'Left', right: 'Right',
        home: 'Home', end: 'End', page_up: 'Prior', page_down: 'Next',
      }.merge((1..12).to_h { |n| [:"f#{n}", "F#{n}"] }).freeze

      # "Ctrl"/"Cmd"/etc, however people spell them -> Tk's own modifier keyword.
      MODIFIER_ALIASES = {
        'ctrl' => 'Control', 'control' => 'Control',
        'alt' => 'Alt', 'option' => 'Alt', 'opt' => 'Alt',
        'shift' => 'Shift',
        'cmd' => 'Command', 'command' => 'Command', 'meta' => 'Meta',
      }.freeze

      # @param spec [Symbol, String] a friendly key (+:enter+) or a
      #   "Modifier-Modifier-Key" string (+"Ctrl-Shift-s"+)
      # @return [Array(Array<String>, String)] [tk_modifiers, tk_keysym]
      def self.resolve(spec)
        return [[], FRIENDLY.fetch(spec) { spec.to_s }] if spec.is_a?(Symbol)

        parts = spec.to_s.split('-')
        base = parts.pop
        keysym = FRIENDLY.fetch(base.downcase.to_sym) { base }
        modifiers = parts.map { |part| MODIFIER_ALIASES.fetch(part.downcase, part) }
        [modifiers, keysym]
      end

      # Tk event patterns to bind for a resolved [modifiers, keysym] pair -
      # usually just one, but Shift+Tab is a known cross-platform gotcha:
      # X11 delivers it as the distinct keysym ISO_Left_Tab, not Tab with a
      # Shift modifier, so binding only <Shift-Tab> silently never fires
      # there. Bind every spelling so the handler fires regardless of
      # platform; on platforms where a given spelling never occurs, that
      # binding is simply inert.
      # @param modifiers [Array<String>]
      # @param keysym [String]
      # @return [Array<String>] Tk bind event patterns, e.g. +["<Control-s>"]+
      def self.patterns_for(modifiers, keysym)
        if keysym == 'Tab' && modifiers.include?('Shift')
          without_shift = modifiers - ['Shift']
          [
            pattern(modifiers, 'Tab'),
            pattern(without_shift, 'ISO_Left_Tab'),
            pattern(modifiers, 'ISO_Left_Tab'),
          ].uniq
        else
          [pattern(modifiers, keysym)]
        end
      end

      class << self
        private

        def pattern(modifiers, keysym)
          "<#{(modifiers + [keysym]).join('-')}>"
        end
      end
    end
  end
end
