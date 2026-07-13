# frozen_string_literal: true

module Teek
  module UI
    # The object yielded to (and returned by) {Teek::UI.app} - the DSL's
    # app-lifecycle surface. Everything else the DSL adds (widgets, layout,
    # events, ...) builds on top of this in later teek-ui work; for now it
    # owns #run/#run_async, the escape hatch to the underlying Teek::App,
    # and thin timer delegates.
    class Session
      # @return [Teek::App] the underlying app - the DSL's escape hatch.
      #   Anything the DSL doesn't wrap yet is one call away: `ui.app.command(...)`.
      attr_reader :app

      # @api private
      def initialize(app)
        @app = app
      end

      # Show the window and enter the Tk event loop. Blocks until the app exits.
      # @return [void]
      def run
        @app.show
        @app.mainloop
      end

      # Show the window without entering the event loop, for interactive/REPL
      # use. Returns immediately.
      #
      # @note this does not (yet) service the event loop automatically between
      #   REPL prompts - call `ui.app.update` yourself to process pending
      #   events while exploring interactively, the same manual-pump workaround
      #   {Teek::App#mainloop}'s own REPL warning documents. A REPL session
      #   helper that services the loop for you on its own is future work,
      #   not built yet.
      # @return [self]
      def run_async
        @app.show
        self
      end

      # @see Teek::App#every
      def every(ms, on_error: :raise, &block)
        @app.every(ms, on_error: on_error, &block)
      end

      # @see Teek::App#after
      def after(ms, on_error: :raise, &block)
        @app.after(ms, on_error: on_error, &block)
      end
    end
  end
end
