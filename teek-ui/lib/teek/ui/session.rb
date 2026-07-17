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

      # A `#every`/`#after` call queued before realize - see {#flush_timers!}.
      # @api private
      Timer = Data.define(:kind, :ms, :on_error, :block)

      # @return [Document] the build-phase tree - constructible and
      #   traversable with no interpreter, before or after realize.
      attr_reader :document

      # @return [Array<Var>] reactive variables declared in this build
      attr_reader :vars

      # @return [Array<Image>] images declared in this build - retained
      #   here for the session's whole lifetime, so a widget's `image:`
      #   never outlives the {Teek::Photo} it points at (see {Image}).
      attr_reader :images

      # @api private
      def initialize(title: nil, scroll: nil, app_opts: {})
        @title = title
        @scroll = scroll
        @app_opts = app_opts
        @document = Document.new
        @stack = [@document.root]
        @scope_stack = [Scope::TOP_LEVEL]
        @vars = []
        @images = []
        @app = nil
        @in_add = false
        @bus = EventBus.new
        @timers = []
        @toast_path = nil
        @toast_timer_id = nil
      end

      # @return [Teek::App] the underlying app - the DSL's escape hatch.
      #   Anything the DSL doesn't wrap yet is one call away: `ui.app.command(...)`.
      # @raise [NotRealizedError] if called before #realize
      def app
        raise_unless_realized!
        @app
      end

      # A live snapshot of currently-registered callbacks, grouped by
      # what registered them - "is my app leaking callbacks, and where."
      # A tag absent from the result means nothing of that kind is
      # currently registered (not a zero entry). Safe to call any time
      # after realize; see `run`/`run_async`'s `debug:` for printing this
      # automatically instead of calling it yourself.
      # @return [Hash{Symbol => Integer}] +:event_bindings+, +:menu_entries+,
      #   +:canvas_item_binds+, +:tag_binds+, +:widget_option_callbacks+
      #   (+-command+/+-textvariable+/etc.), +:window_close_handlers+
      # @raise [NotRealizedError] if called before #realize
      def debug_info
        raise_unless_realized!
        counts = @app.callback_registry.counts_by_tag
        {
          event_bindings: counts[:bind],
          menu_entries: counts[:menu],
          canvas_item_binds: counts[:canvas_bind],
          tag_binds: counts[:tag_bind],
          widget_option_callbacks: counts[:widget_option],
          window_close_handlers: counts[:wm_protocol],
        }.reject { |_, count| count.zero? }
      end

      # Reverse lookup: given a real Tk path (from an error message, a
      # +winfo+ query, or poking around in a REPL), find which widget it
      # belongs to - the counterpart to the name-based +ui[:name]+. See
      # {Document#find_by_path} for exactly what counts as a match.
      # @param path [String] e.g. +".toolbar.save"+
      # @return [Handle, nil]
      # @raise [NotRealizedError] if called before #realize
      def find_by_path(path)
        raise_unless_realized!
        node = @document.find_by_path(path)
        node && Handle.new(node)
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
          # vars/images realize first, so a widget bound/pointed to one
          # displays correctly (a value, a loaded image) from the moment
          # it's created instead of starting blank/broken.
          @vars.each { |v| v.realize(app) }
          @images.each { |img| img.realize(app) }
          Realizer.new(app, @document, default_scroll: @scroll).realize
          flush_timers!(app)
        rescue
          app.destroy
          raise
        end
        @app = app
      end

      # Realize, show the window, and enter the Tk event loop. Blocks until
      # the app exits.
      # @param strict [Boolean] see {Validator.validate!}
      # @param debug [Boolean] print {#debug_info}'s summary to stderr,
      #   once right before entering the event loop and once after it
      #   returns - eyeball whether the app leaked any callbacks over
      #   its run without writing any diagnostic code yourself.
      # @return [void]
      def run(strict: false, debug: false)
        realize(strict: strict)
        @app.show
        print_debug_info if debug
        @app.mainloop
        print_debug_info if debug
      end

      # Realize and show the window without entering the event loop. Returns
      # immediately - the caller is responsible for servicing the event loop
      # from then on (e.g. its own timer/callback-driven flow).
      #
      # @note Not a substitute for {#run} in an interactive REPL (IRB/Pry):
      #   nothing services the event loop while the REPL blocks waiting for
      #   your next line, so the window beachballs between commands on macOS
      #   no matter how often you call `ui.app.update` by hand - see
      #   {Teek::App#mainloop}'s own REPL warning. Driving a session
      #   interactively from IRB/Pry isn't a supported workflow.
      # @param strict [Boolean] see {Validator.validate!}
      # @param debug [Boolean] print {#debug_info}'s summary to stderr
      #   right after realize
      # @return [self]
      def run_async(strict: false, debug: false)
        realize(strict: strict)
        @app.show
        print_debug_info if debug
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

      # Same queue-then-wire shape as an `on_*` event binding: called
      # inside the build block, it queues and registers once the tree
      # realizes; called after, it registers immediately - same method,
      # correct behavior either way, so a tick loop can be declared right
      # alongside the UI it drives instead of being forced out to a
      # separate post-`run_async` step.
      # @see Teek::App#every
      # @return [Object, nil] the live timer object (`.cancel`-able) once
      #   realized; `nil` if queued - there's no live timer to hand back
      #   yet, since nothing has registered with Tcl at that point
      def every(ms, on_error: :raise, &block)
        if @app
          @app.every(ms, on_error: on_error, &block)
        else
          @timers << Timer.new(kind: :every, ms: ms, on_error: on_error, block: block)
          nil
        end
      end

      # @see #every
      # @see Teek::App#after
      # @return [Object, nil] see {#every}
      def after(ms, on_error: :raise, &block)
        if @app
          @app.after(ms, on_error: on_error, &block)
        else
          @timers << Timer.new(kind: :after, ms: ms, on_error: on_error, block: block)
          nil
        end
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

      # Show a busy cursor over +window+ for the duration of the block -
      # {Teek::App#busy} already restores it even if the block raises,
      # nothing extra to do here for that.
      # @param window [String] Tk window path
      # @yield the work to perform while busy
      # @return the block's return value
      # @raise [NotRealizedError] if called before #realize
      def busy(window: '.', &block)
        raise_unless_realized!
        @app.busy(window: window, &block)
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

      # Milliseconds a {#toast} stays visible when no +duration:+ is given.
      DEFAULT_TOAST_DURATION_MS = 1500

      # Briefly flash a message near the bottom of the window - "Saved"
      # after a save action, "Settings" when a modal gains focus, that
      # kind of transient feedback, not a persistent status. Reuses one
      # widget across every call rather than building a new one each
      # time: calling this again while a toast is already showing
      # replaces it (new text, restarted timer) instead of stacking a
      # second one, and the earlier toast's own pending auto-dismiss is
      # cancelled so it can never fire late and hide the replacement.
      # @param message [String]
      # @param duration [Integer] milliseconds before it auto-dismisses
      # @return [void]
      # @raise [NotRealizedError] if called before #realize
      def toast(message, duration: DEFAULT_TOAST_DURATION_MS)
        raise_unless_realized!
        ensure_toast_widget
        @app.command(@toast_path, :configure, text: message)
        @app.command(:place, @toast_path, in: '.', relx: 0.5, rely: 1.0, anchor: 's', y: -12)
        @app.after_cancel(@toast_timer_id) if @toast_timer_id
        @toast_timer_id = @app.after(duration) { @app.command(:place, :forget, @toast_path) }
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
        vars_before = @vars.length
        images_before = @images.length
        push_stack(parent_node)
        @in_add = true
        begin
          yield self if block_given?
        ensure
          @in_add = false
          pop_stack
        end

        # A var/image declared inside this block needs to be real before
        # the new widget subtree realizes, exactly like the initial
        # #realize orders them - a widget referencing one via
        # bind:/image: assumes it's already backed by the time IT gets
        # created (see Var#realize/Image#realize).
        @vars[vars_before..].each { |v| v.realize(@app) }
        @images[images_before..].each { |img| img.realize(@app) }

        realizer = Realizer.new(@app, @document, default_scroll: @scroll)
        # A lazy: true child built in this block (see WidgetDSL#append_container)
        # stays unrealized here too, exactly like one built during the
        # initial realize - it's realized later, on demand (see Handle#realize!).
        parent_node.children[before..].each { |child| realizer.realize_subtree(child, parent_node) unless child.lazy? }

        nil
      end

      private

      # Creates the one toast label this session will ever need, the
      # first time {#toast} is called - a no-op on every later call.
      # Claims its path segment through {Document#claim_path_segment}
      # like any ordinary widget would, so the vanishingly unlikely case
      # of a build already using +:toast+ as a top-level widget name
      # gets disambiguated instead of silently colliding with it.
      def ensure_toast_widget
        return if @toast_path

        segment = @document.claim_path_segment('.', 'toast')
        @toast_path = ".#{segment}"
        @app.command('ttk::label', @toast_path, background: '#323232', foreground: 'white', padding: [14, 8])
      end

      # Registers every timer queued via `#every`/`#after` before realize
      # against the now-live +app+, in declaration order - mirrors how
      # {Realizer#link} wires queued event bindings once the whole tree
      # is up. Called from inside #realize's own begin block (not after
      # +@app+ is set), so a bad timer registration is caught by the
      # SAME atomicity guarantee as the rest of realize.
      def flush_timers!(app)
        @timers.each do |timer|
          case timer.kind
          when :every then app.every(timer.ms, on_error: timer.on_error, &timer.block)
          when :after then app.after(timer.ms, on_error: timer.on_error, &timer.block)
          end
        end
        @timers.clear
      end

      def raise_unless_realized!
        raise NotRealizedError unless @app
      end

      # @see #run, #run_async's own +debug:+ - always stderr, never
      # stdout (this is diagnostics, not program output).
      def print_debug_info
        warn "[teek-ui debug] live callbacks: #{debug_info}"
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
