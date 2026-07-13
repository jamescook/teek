# frozen_string_literal: true

require_relative 'errors'
require_relative 'document'
require_relative 'widget_dsl'
require_relative 'realizer'

module Teek
  module UI
    # The object yielded to (and returned by) {Teek::UI.app} - owns the
    # build-phase {Document} and the realize/run lifecycle, and (via
    # {WidgetDSL}) the `ui.<widget>` build surface itself.
    #
    # Building is Tk-free: {Teek::UI.app} never constructs a {Teek::App}, so
    # the block runs (and #document is buildable/inspectable) with no
    # interpreter at all. Nothing talks to Tk until #realize (called by #run
    # and #run_async, or directly) actually creates one and walks the tree
    # into it via {Realizer}.
    class Session
      include WidgetDSL

      # @return [Document] the build-phase tree - constructible and
      #   traversable with no interpreter, before or after realize.
      attr_reader :document

      # @api private
      def initialize(title: nil, app_opts: {})
        @title = title
        @app_opts = app_opts
        @document = Document.new
        @stack = [@document.root]
        @app = nil
      end

      # @return [Teek::App] the underlying app - the DSL's escape hatch.
      #   Anything the DSL doesn't wrap yet is one call away: `ui.app.command(...)`.
      # @raise [NotRealizedError] if called before #realize
      def app
        raise_unless_realized!
        @app
      end

      # Create the underlying {Teek::App} and realize the build tree into it,
      # if that hasn't happened yet. Idempotent - calling it again after the
      # first time just returns the same app.
      #
      # Atomic: the app's root window starts (and stays) withdrawn until the
      # whole tree is realized, so a mid-realize error never leaves a
      # half-built window visible. On failure the partially-built app is
      # destroyed and the session is left exactly as if #realize had never
      # been called - it isn't left half-realized.
      # @return [Teek::App]
      def realize
        return @app if @app

        app = Teek::App.new(title: @title, **@app_opts)
        begin
          Realizer.realize(app, @document)
        rescue
          app.destroy
          raise
        end
        @app = app
      end

      # Realize, show the window, and enter the Tk event loop. Blocks until
      # the app exits.
      # @return [void]
      def run
        realize
        @app.show
        @app.mainloop
      end

      # Realize and show the window without entering the event loop, for
      # interactive/REPL use. Returns immediately.
      #
      # @note this does not (yet) service the event loop automatically between
      #   REPL prompts - call `ui.app.update` yourself to process pending
      #   events while exploring interactively, the same manual-pump workaround
      #   {Teek::App#mainloop}'s own REPL warning documents. A REPL session
      #   helper that services the loop for you on its own is future work,
      #   not built yet.
      # @return [self]
      def run_async
        realize
        @app.show
        self
      end

      # @see Teek::App#every
      # @raise [NotRealizedError] if called before #realize
      def every(ms, on_error: :raise, &block)
        raise_unless_realized!
        @app.every(ms, on_error: on_error, &block)
      end

      # @see Teek::App#after
      # @raise [NotRealizedError] if called before #realize
      def after(ms, on_error: :raise, &block)
        raise_unless_realized!
        @app.after(ms, on_error: on_error, &block)
      end

      private

      def raise_unless_realized!
        raise NotRealizedError unless @app
      end
    end
  end
end
