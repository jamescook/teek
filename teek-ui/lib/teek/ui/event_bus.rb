# frozen_string_literal: true

module Teek
  module UI
    # In-process publish/subscribe for decoupled app events (+:item_selected+,
    # +:theme_changed+) - not Tk events, complementary to
    # {Handle#on_click}/{Handle#on_key}. Reach for this only when a direct
    # handle or a shared reactive {Var} would couple things that should
    # stay decoupled.
    #
    # Owned by one {Session} (+ui.on+/+ui.emit+/+ui.off+) - two separate
    # {Teek::UI.app} instances in the same process never share a bus. Pure
    # Ruby, no Tk/interpreter involved, so it works before realize too.
    class EventBus
      # @api private
      def initialize
        @listeners = Hash.new { |h, k| h[k] = [] }
      end

      # Subscribe to a named event.
      # @param event [Symbol]
      # @yield the subscriber, called with whatever {#emit} was given
      # @return [Proc] the block, to pass to a later {#off}
      def on(event, &block)
        @listeners[event] << block
        block
      end

      # Emit a named event to every current subscriber, in subscription order.
      # @param event [Symbol]
      # @param args [Array] forwarded to each subscriber
      # @param kwargs [Hash] forwarded to each subscriber
      # @return [void]
      def emit(event, *args, **kwargs)
        if kwargs.empty?
          @listeners[event].each { |listener| listener.call(*args) }
        else
          @listeners[event].each { |listener| listener.call(*args, **kwargs) }
        end
        nil
      end

      # Unsubscribe a specific listener.
      # @param event [Symbol]
      # @param block [Proc] the block {#on} returned
      # @return [void]
      def off(event, block)
        @listeners[event].delete(block)
        nil
      end
    end
  end
end
