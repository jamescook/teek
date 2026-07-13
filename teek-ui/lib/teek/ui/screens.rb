# frozen_string_literal: true

module Teek
  module UI
    # Push/pop stack for content screens - works directly against ordinary
    # DSL handles (a `ui.panel`/`ui.box`, or a `ui.window`) instead of
    # requiring a bespoke per-screen class with its own show/hide/cleanup
    # protocol. Pushing conceals the current screen (if any) before
    # revealing the new one; popping reverses it, re-revealing whatever is
    # now on top.
    #
    # A `:window` handle is revealed/concealed through its own {Handle#show}/
    # {Handle#hide} (deiconify/raise/modal, or grab-release/withdraw);
    # anything else is packed to fill its parent, or pack-forgotten via the
    # plain `pack`/`pack forget` primitive.
    #
    # @example
    #   ui.screens.push(:picker, ui[:picker])
    #   ui.screens.push(:emulator, ui[:emulator])   # picker concealed
    #   ui.screens.pop                              # emulator concealed, picker revealed
    #   ui.screens.replace_current(ui[:emulator])   # in-place swap, same stack depth
    class Screens
      Entry = Data.define(:name, :screen)

      # @api private
      def initialize
        @stack = []
      end

      # @return [Boolean] true if any screen is on the stack
      def active?
        !@stack.empty?
      end

      # @return [Symbol, nil] name of the topmost screen
      def current
        @stack.last&.name
      end

      # @return [Handle, nil] the topmost screen's handle
      def current_screen
        @stack.last&.screen
      end

      # @return [Integer] number of screens on the stack
      def size
        @stack.length
      end

      # Push a screen onto the stack. The previous screen (if any) is
      # concealed before the new one is revealed.
      # @param name [Symbol] identifier (e.g. +:picker+, +:emulator+)
      # @param screen [Handle] a +:window+ handle, or any other container/widget handle
      # @return [void]
      def push(name, screen)
        conceal(@stack.last.screen) if @stack.last
        @stack.push(Entry.new(name: name, screen: screen))
        reveal(screen)
        nil
      end

      # Replace the current screen in-place, without changing stack depth -
      # the existing screen is concealed, the new one takes its name and is
      # revealed.
      # @param screen [Handle]
      # @return [void]
      def replace_current(screen)
        entry = @stack.last or return
        conceal(entry.screen)
        @stack[-1] = Entry.new(name: entry.name, screen: screen)
        reveal(screen)
        nil
      end

      # Pop the current screen off the stack. The popped screen is
      # concealed; if a screen remains underneath, it's revealed again.
      # @return [void]
      def pop
        entry = @stack.pop or return
        conceal(entry.screen)
        reveal(@stack.last.screen) if @stack.last
        nil
      end

      private

      def reveal(screen)
        if screen.type == :window
          screen.show
        else
          screen.app.command(:pack, screen.path, fill: :both, expand: 1)
        end
      end

      def conceal(screen)
        if screen.type == :window
          screen.hide
        else
          screen.app.command(:pack, :forget, screen.path)
        end
      end
    end
  end
end
