# frozen_string_literal: true

require_relative 'errors'
require_relative 'document'
require_relative 'widget_dsl'
require_relative 'realizer'
require_relative 'validator'
require_relative 'event_bus'
require_relative 'scope'

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

      # @return [Array<Var>] reactive variables declared in this build
      attr_reader :vars

      # @api private
      def initialize(title: nil, scroll: nil, app_opts: {})
        @title = title
        @scroll = scroll
        @app_opts = app_opts
        @document = Document.new
        @stack = [@document.root]
        @scope_stack = [Scope::TOP_LEVEL]
        @vars = []
        @app = nil
        @in_add = false
        @bus = EventBus.new
      end

      # @return [Teek::App] the underlying app - the DSL's escape hatch.
      #   Anything the DSL doesn't wrap yet is one call away: `ui.app.command(...)`.
      # @raise [NotRealizedError] if called before #realize
      def app
        raise_unless_realized!
        @app
      end

      # Validate the build tree, then create the underlying {Teek::App} and
      # realize the tree into it, if that hasn't happened yet. Idempotent -
      # calling it again after the first time just returns the same app.
      #
      # Atomic in two senses: a validation failure means no interpreter is
      # ever constructed at all, and even once realizing starts, the app's
      # root window stays withdrawn until the whole tree is realized, so a
      # mid-realize error never leaves a half-built window visible either
      # way. On failure the session is left exactly as if #realize had never
      # been called - it isn't left half-realized (or half-validated).
      # @param strict [Boolean] see {Validator.validate!}
      # @return [Teek::App]
      # @raise [ValidationError] if the build tree has problems
      def realize(strict: false)
        return @app if @app

        Validator.validate!(@document, strict: strict)

        app = Teek::App.new(title: @title, **@app_opts)
        begin
          # vars realize first, so a widget bound to one displays its
          # initial value immediately instead of starting blank.
          @vars.each { |v| v.realize(app) }
          Realizer.new(app, @document, default_scroll: @scroll).realize
        rescue
          app.destroy
          raise
        end
        @app = app
      end

      # Realize, show the window, and enter the Tk event loop. Blocks until
      # the app exits.
      # @param strict [Boolean] see {Validator.validate!}
      # @return [void]
      def run(strict: false)
        realize(strict: strict)
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
      # @param strict [Boolean] see {Validator.validate!}
      # @return [self]
      def run_async(strict: false)
        realize(strict: strict)
        @app.show
        self
      end

      # @see EventBus#on
      # @return [Proc] the block, to pass to a later #off
      def on(event, &block)
        @bus.on(event, &block)
      end

      # @see EventBus#emit
      # @return [void]
      def emit(event, *args, **kwargs)
        @bus.emit(event, *args, **kwargs)
      end

      # @see EventBus#off
      # @return [void]
      def off(event, block)
        @bus.off(event, block)
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

      # Show the native "choose file to open" dialog.
      # @see Teek::App#choose_open_file
      # @raise [NotRealizedError] if called before #realize
      def open_file(filetypes: nil, initialdir: nil, initialfile: nil, title: nil, multiple: false, parent: nil)
        raise_unless_realized!
        @app.choose_open_file(filetypes: filetypes, initialdir: initialdir, initialfile: initialfile,
                               title: title, multiple: multiple, parent: parent)
      end

      # Show the native "choose file to save" dialog.
      # @see Teek::App#choose_save_file
      # @raise [NotRealizedError] if called before #realize
      def save_file(filetypes: nil, initialdir: nil, initialfile: nil, title: nil,
                     defaultextension: nil, confirmoverwrite: true, parent: nil)
        raise_unless_realized!
        @app.choose_save_file(filetypes: filetypes, initialdir: initialdir, initialfile: initialfile, title: title,
                               defaultextension: defaultextension, confirmoverwrite: confirmoverwrite, parent: parent)
      end

      # Show a message box with one or more buttons.
      # @see Teek::App#message_box
      # @raise [NotRealizedError] if called before #realize
      def message(message:, title: nil, detail: nil, icon: :info, type: :ok, default: nil, parent: nil)
        raise_unless_realized!
        @app.message_box(message: message, title: title, detail: detail, icon: icon,
                          type: type, default: default, parent: parent)
      end

      # Show the native color picker dialog.
      # @see Teek::App#choose_color
      # @raise [NotRealizedError] if called before #realize
      def choose_color(initial: nil, title: nil, parent: nil)
        raise_unless_realized!
        @app.choose_color(initial: initial, title: title, parent: parent)
      end

      # Show the native "choose directory" dialog.
      # @see Teek::App#choose_dir
      # @raise [NotRealizedError] if called before #realize
      def choose_dir(initialdir: nil, mustexist: false, title: nil, parent: nil)
        raise_unless_realized!
        @app.choose_dir(initialdir: initialdir, mustexist: mustexist, title: title, parent: parent)
      end

      # @return [Teek::Clipboard] +.set(text)+/+.get+/+.clear+ - text
      #   widgets don't need this at all for their own copy/cut/paste
      #   (Tk wires that to the platform's expected keys already); this is
      #   for reading/writing the clipboard directly from app code.
      # @raise [NotRealizedError] if called before #realize
      def clipboard
        raise_unless_realized!
        @app.clipboard
      end

      # Build and immediately realize a subtree into the already-running
      # app, as a child of an already-realized widget named +parent_name+ -
      # for dynamic UIs (adding cards/rows/menu entries at runtime), not
      # just the initial build. The block uses the exact same widget DSL as
      # everywhere else (`a.button(...)`, `a.column(...) { }`, ...); new
      # widgets show up immediately, routed through the same
      # {Teek::App#command}/leak-cleanup path the initial realize uses, so
      # destroying an added widget reclaims its callbacks the normal way.
      #
      # Unlike the initial #realize, this does not run {Validator} - it's
      # already-known-good territory (the session realized once already);
      # validating one small addition on every call would be wasted work.
      # @param parent_name [Symbol] an already-realized widget's name
      # @yieldparam ui [Session] the same builder, block-scoped under +parent_name+
      # @return [nil]
      # @raise [NotRealizedError] if the session, or the named parent, isn't realized yet
      # @raise [ArgumentError] if no widget is declared under +parent_name+
      def add(parent_name)
        raise_unless_realized!

        parent_node = @document.find(parent_name) or
          raise ArgumentError, "no widget named :#{parent_name} in this build"
        raise NotRealizedError, "##{parent_name} is not realized yet" unless parent_node.realized

        before = parent_node.children.length
        @stack.push(parent_node)
        @in_add = true
        begin
          yield self if block_given?
        ensure
          @in_add = false
          @stack.pop
        end

        realizer = Realizer.new(@app, @document, default_scroll: @scroll)
        # A lazy: true child built in this block (see WidgetDSL#append_container)
        # stays unrealized here too, exactly like one built during the
        # initial realize - it's realized later, on demand (see Handle#realize!).
        parent_node.children[before..].each { |child| realizer.realize_subtree(child, parent_node) unless child.lazy? }

        nil
      end

      private

      def raise_unless_realized!
        raise NotRealizedError unless @app
      end

      # @return [Boolean] whether {WidgetDSL}'s build methods (ui.button,
      #   ui.panel, ui.raw, ui.var, ...) are still allowed to append to the
      #   tree - true before the initial realize, and again for the
      #   duration of an {#add} block (which re-opens it, scoped to that
      #   one call), false everywhere else. See {WidgetDSL#raise_if_closed!}.
      def build_open?
        @app.nil? || @in_add
      end
    end
  end
end
