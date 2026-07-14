# frozen_string_literal: true

require 'teek/platform'

module Teek
  module UI
    # @api private
    #
    # Shared mouse-event vocabulary between {Handle} and {CanvasItem}'s own
    # +on_right_click+, so both mean exactly the same "right click, however
    # the platform spells it" and "these are the two things you're allowed
    # to pop up."
    module MouseEvents
      # A right click, however the platform spells it - the real right
      # mouse button everywhere (+<Button-3>+), plus macOS's two long-
      # standing secondary-click gestures (+<Button-2>+, and
      # +<Control-Button-1>+ from the one-button-mouse era) - NOT bound on
      # other platforms, where Ctrl+click carries no such meaning (and on
      # X11 specifically, Button-2 is the middle mouse button, a real,
      # distinct button of its own) - binding them unconditionally there
      # would silently fire a "right click" handler on gestures users
      # never intended as one.
      RIGHT_CLICK_EVENTS = (
        Teek.platform.darwin? ? %w[<Button-2> <Button-3> <Control-Button-1>] : %w[<Button-3>]
      ).freeze

      # Handle types +on_right_click(menu)+ accepts to pop up.
      MENU_HANDLE_TYPES = %i[menu context_menu].freeze
    end
  end
end
