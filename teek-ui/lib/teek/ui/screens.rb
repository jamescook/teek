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
    # A screen being pushed/replaced-in can also be a `lazy: true` node
    # that hasn't been realized yet (see {WidgetDSL#append_container}) -
    # it's realized on demand, right before being revealed, with nothing
    # extra to call by hand, as long as this stack was constructed with
    # `document:`. A screen with no opinion on laziness at all (any plain
    # object exposing just `type`/`path`/`app` or `type`/`show`/`hide`,
    # the original "push an already-built Handle" usage) behaves exactly
    # as before either way. Concealing never destroys a screen's widget -
    # see {Handle#destroy!} for that as a separate, explicit step
    # (typically `screens.pop&.destroy!`).
    #
    # @example
    #   ui.screens.push(:picker, ui[:picker])
    #   ui.screens.push(:emulator, ui[:emulator])   # picker concealed
    #   ui.screens.pop                              # emulator concealed, picker revealed
    #   ui.screens.replace_current(ui[:emulator])   # in-place swap, same stack depth
    class Screens
      Entry = Data.define(:name, :screen)

      # @api private
      # @param document [Document, nil] needed only to lazily {Handle#realize!}
      #   a not-yet-realized screen on push - omit if every screen pushed
      #   onto this stack is already realized
      def initialize(document: nil)
        @stack = []
        @document = document
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
      # concealed before the new one is realized (if it isn't already)
      # and revealed.
      # @param name [Symbol] identifier (e.g. +:picker+, +:emulator+)
      # @param screen [Handle] a +:window+ handle, or any other container/widget handle
      # @return [void]
      def push(name, screen)
        conceal(@stack.last.screen) if @stack.last
        @stack.push(Entry.new(name: name, screen: screen))
        ensure_realized(screen)
        reveal(screen)
        nil
      end

      # Replace the current screen in-place, without changing stack depth -
      # the existing screen is concealed, the new one takes its name,
      # realizes if needed, and is revealed.
      # @param screen [Handle]
      # @return [void]
      def replace_current(screen)
        entry = @stack.last or return
        conceal(entry.screen)
        @stack[-1] = Entry.new(name: entry.name, screen: screen)
        ensure_realized(screen)
        reveal(screen)
        nil
      end

      # Pop the current screen off the stack. The popped screen is
      # concealed (never destroyed - see {Handle#destroy!} to additionally
      # release it); if a screen remains underneath, it's revealed again.
      # @return [Object, nil] the just-popped screen, or +nil+ if the stack was empty
      def pop
        entry = @stack.pop or return nil
        conceal(entry.screen)
        reveal(@stack.last.screen) if @stack.last
        entry.screen
      end

      private

      # +realized?+/+realize!+ are internal on {Handle} (an app author
      # never triggers this by hand - a `lazy: true` screen just works
      # through {#push}/{#replace_current}) - `respond_to?(..., true)`
      # and `send` reach past that on purpose, since this IS one of
      # {Handle#realize!}'s two intended callers. A screen with no
      # opinion on laziness at all (doesn't respond to +realized?+, even
      # privately - the original "push an already-built Handle" usage)
      # skips this entirely, exactly as before.
      def ensure_realized(screen)
        return unless screen.respond_to?(:realized?, true) && !screen.send(:realized?)

        unless @document
          raise ArgumentError, "this screen isn't realized yet and this Screens has no document: to realize it with"
        end

        screen.send(:realize!, @document)
      end

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
