# frozen_string_literal: true

require_relative 'screens'

module Teek
  module UI
    # Push/pop stack for modal window handles, so one modal can push
    # another (e.g. Settings -> Replay Player) with the previous modal
    # automatically re-shown once the new one is dismissed.
    #
    # The reveal/conceal-on-transition bookkeeping - including on-demand
    # {Handle#realize!} of a not-yet-realized `lazy: true` modal, given
    # `document:` (a "child window" opened fresh each time, say) - is
    # exactly what {Screens} already does, so this wraps one internally
    # rather than re-deriving it. What's actually different here is the
    # on_enter/on_exit/on_focus_change lifecycle, useful for pause/resume-
    # style hooks (e.g. pausing an emulator while any modal is open). Each
    # window handle pushed here should typically be declared `modal: true`
    # (as `ui.dialog` already defaults to) for `Handle#show` to actually
    # grab input - ModalStack itself does no grabbing of its own.
    #
    # @example
    #   ui.modal = Teek::UI::ModalStack.new(
    #     on_enter: ->(name) { pause_emulation },
    #     on_exit: -> { unpause_emulation },
    #     on_focus_change: ->(name) { update_toast(name) },
    #   )
    #   ui.modal.push(:settings, ui[:settings])
    #   ui.modal.push(:replay, ui[:replay])   # settings auto-withdrawn
    #   ui.modal.pop                          # replay closed, settings re-shown
    #   ui.modal.pop                          # settings closed, on_exit fires
    class ModalStack
      # @param on_enter [Proc] called with (name) when the stack goes empty -> non-empty
      # @param on_exit [Proc] called with no arguments when the stack goes non-empty -> empty
      # @param on_focus_change [Proc, nil] called with (name) whenever the top modal changes -
      #   every push, and every pop that leaves a modal underneath (not the final pop, which
      #   fires on_exit instead)
      # @param document [Document, nil] forwarded to the internal {Screens}
      #   - see {Screens#initialize} - needed only to lazily {Handle#realize!}
      #   a not-yet-realized modal on push
      def initialize(on_enter:, on_exit:, on_focus_change: nil, document: nil)
        @screens = Screens.new(document: document)
        @on_enter = on_enter
        @on_exit = on_exit
        @on_focus_change = on_focus_change
      end

      # @return [Boolean] true if any modal is open
      def active?
        @screens.active?
      end

      # @return [Symbol, nil] name of the topmost modal
      def current
        @screens.current
      end

      # @return [Integer] number of modals on the stack
      def size
        @screens.size
      end

      # Push a modal window handle onto the stack. Whatever was on top (if
      # any) is withdrawn first, with no callback of its own - it's
      # stepping aside, not being dismissed. `on_enter` fires only if the
      # stack was empty; `on_focus_change` fires unconditionally.
      # @param name [Symbol]
      # @param window [Handle] a `:window` handle
      # @return [void]
      def push(name, window)
        was_empty = !@screens.active?

        @screens.push(name, window)

        @on_enter.call(name) if was_empty
        @on_focus_change&.call(name)
        nil
      end

      # Pop the current modal off the stack. If a modal remains
      # underneath, it's re-shown (by {Screens#pop}) and `on_focus_change`
      # fires for it; otherwise the stack is now empty and `on_exit` fires
      # instead.
      # @return [Object, nil] the just-popped window, or +nil+ if the stack was empty
      def pop
        return nil unless @screens.active?

        popped = @screens.pop

        if @screens.active?
          @on_focus_change&.call(@screens.current)
        else
          @on_exit.call
        end
        popped
      end
    end
  end
end
