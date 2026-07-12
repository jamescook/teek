# frozen_string_literal: true

require 'tcltklib'
require_relative 'teek/version'
require_relative 'teek/platform'
require_relative 'teek/ractor_support'
require_relative 'teek/widget'
require_relative 'teek/callback_registry'
require_relative 'teek/tag_bindable'
require_relative 'teek/menu_behavior'
require_relative 'teek/text_behavior'
require_relative 'teek/treeview_behavior'
require_relative 'teek/photo'

# Ruby interface to Tcl/Tk. Provides a thin wrapper around a Tcl interpreter
# with Ruby callbacks, event bindings, and background work support.
#
# The main entry point is {Teek::App}, which initializes Tcl/Tk and provides
# methods for evaluating Tcl code, creating widgets, and running the event loop.
#
# @example Basic usage
#   app = Teek::App.new
#   app.command('ttk::button', '.btn', text: 'Click', command: proc { puts "hi" })
#   app.command(:pack, '.btn')
#   app.show
#   app.mainloop
#
# @example Background work (keeps UI responsive)
#   app.background_work(urls, mode: :thread) do |task, data|
#     data.each { |url| task.yield(fetch(url)) }
#   end.on_progress { |result| update_ui(result) }
#      .on_done { puts "Finished" }
#
# @see Teek::App
# @see Teek::BackgroundWork
module Teek

  def self.bool_to_tcl(val)
    val ? "1" : "0"
  end

  WIDGET_COMMANDS = %w[
    button label frame entry text canvas listbox
    scrollbar scale spinbox menu menubutton message
    panedwindow labelframe checkbutton radiobutton
    toplevel
    ttk::button ttk::label ttk::frame ttk::entry
    ttk::combobox ttk::checkbutton ttk::radiobutton
    ttk::scale ttk::scrollbar ttk::spinbox ttk::separator
    ttk::sizegrip ttk::progressbar ttk::notebook
    ttk::panedwindow ttk::labelframe ttk::menubutton
    ttk::treeview
  ].freeze

  class App
    attr_reader :interp, :widgets, :debugger, :callback_registry
    attr_writer :_pending_exception # @api private

    def initialize(title: nil, track_widgets: true, debug: false, &block)
      @interp = Teek::Interp.new
      @interp.tcl_eval('package require Tk')
      hide
      @widgets = {}
      @widget_counters = Hash.new(0)
      @callback_registry = Teek::CallbackRegistry.new(self)
      @menu_command_warned = {}
      @tag_bind_warned = {}
      @_pending_exception = nil
      debug ||= !!ENV['TEEK_DEBUG']
      track_widgets = true if debug
      @track_widgets = track_widgets
      setup_widget_tracking if track_widgets
      setup_destroy_cleanup
      if debug
        require_relative 'teek/debugger'
        @debugger = Teek::Debugger.new(self)
      end
      set_window_title(title) if title
      instance_eval(&block) if block
    end

    # Evaluate a raw Tcl script string and return the result.
    # Prefer {#command} for building commands from Ruby values; use this
    # when you need Tcl-level features like variable substitution or
    # inline expressions that {#command} can't express.
    # @param script [String] Tcl code to evaluate
    # @return [String] the Tcl result
    def tcl_eval(script)
      @interp.tcl_eval(script)
    end

    # Invoke a Tcl command with pre-split arguments (no Tcl parsing).
    # Safer than {#tcl_eval} when arguments may contain special characters.
    # @param args [Array<String>] command name followed by arguments
    # @return [String] the Tcl result
    def tcl_invoke(*args)
      @interp.tcl_invoke(*args)
    end

    # Register a Ruby callable as a Tcl callback.
    # The callable can use +throw+ for Tcl control flow:
    #   throw :teek_break    - stop event propagation (like Tcl "break")
    #   throw :teek_continue - Tcl TCL_CONTINUE
    #   throw :teek_return   - Tcl TCL_RETURN
    #
    # +:teek_break+/+:teek_continue+ only mean something when Tcl actually
    # dispatches the result through a context that knows how to handle
    # TCL_BREAK/TCL_CONTINUE - Tk's bind mechanism does; a plain script
    # invocation (a menu entry's or widget's `-command`) does not, and
    # returning either code there is a Tcl error ("invoked break/continue
    # outside of a loop"), not a no-op. +relay_break_continue: false+ is
    # for exactly those non-bind callers: +throw+ is still caught (so it
    # can't crash as an uncaught throw), but is treated as the callback
    # simply finishing, instead of being relayed to Tcl. +:teek_return+ is
    # always relayed either way - TCL_RETURN is safe in any context.
    # @param callable [#call] a Proc or lambda to invoke from Tcl
    # @param relay_break_continue [Boolean] whether a caught :teek_break/
    #   :teek_continue is relayed to Tcl as TCL_BREAK/TCL_CONTINUE (true,
    #   for bind-dispatched callbacks) or silently absorbed (false, for
    #   callbacks invoked as a plain script - menu/widget -command options)
    # @return [Integer] callback ID, usable as +ruby_callback <id>+ in Tcl
    # @see #unregister_callback
    def register_callback(callable, relay_break_continue: true)
      wrapped = proc { |*args|
        caught = nil
        catch(:teek_break) do
          catch(:teek_continue) do
            catch(:teek_return) do
              callable.call(*args)
              caught = :_none
            end
            caught ||= :return
          end
          caught ||= :continue
        end
        caught ||= :break
        next nil if caught == :_none
        next caught if caught == :return
        relay_break_continue ? caught : nil
      }
      @interp.register_callback(wrapped)
    end

    # Remove a previously registered callback by its ID.
    # @param id [Integer] callback ID returned by {#register_callback}
    # @return [void]
    def unregister_callback(id)
      @interp.unregister_callback(id)
    end

    # Evaluate +script+ once per App instance under +name+, skipping it on
    # later calls. Meant for widget-behavior modules that need to define a
    # Tcl-side helper proc (e.g. a scan routine) without re-sending and
    # re-parsing that definition on every call.
    # @param name [Symbol] unique name for this helper
    # @yieldreturn [String] the Tcl script to evaluate the first time
    # @return [void]
    def ensure_tcl_helper(name)
      @installed_tcl_helpers ||= {}
      return if @installed_tcl_helpers[name]
      @interp.tcl_eval(yield)
      @installed_tcl_helpers[name] = true
    end

    # Schedule a one-shot timer. Calls the block after +ms+ milliseconds.
    # @param ms [Integer] delay in milliseconds
    # @param on_error [:raise, Proc, nil] error handling strategy:
    #   - +:raise+ (default) — exception propagates to Tcl background error handler.
    #   - +Proc+ — called with the exception; error is swallowed.
    #   - +nil+ — error is silently swallowed.
    # @yield block to call when the timer fires
    # @return [String] timer ID, pass to {#after_cancel} to cancel
    # @see https://www.tcl-lang.org/man/tcl8.6/TclCmd/after.htm#M5 after ms
    def after(ms, on_error: :raise, &block)
      cb_id = nil
      cb_id = @interp.register_callback(proc { |*|
        begin
          block.call
        rescue => e
          raise if on_error == :raise
          on_error.call(e) if on_error.is_a?(Proc)
        ensure
          @interp.unregister_callback(cb_id)
        end
      })
      after_id = @interp.tcl_eval("after #{ms.to_i} {ruby_callback #{cb_id}}")
      after_id.instance_variable_set(:@cb_id, cb_id)
      after_id
    end

    # Schedule a block to run once when the event loop is idle.
    # @yield block to call when the event loop is idle
    # @return [String] timer ID, pass to {#after_cancel} to cancel
    # @see https://www.tcl-lang.org/man/tcl8.6/TclCmd/after.htm#M9 after idle
    def after_idle(&block)
      cb_id = nil
      cb_id = @interp.register_callback(proc { |*|
        block.call
        @interp.unregister_callback(cb_id)
      })
      after_id = @interp.tcl_eval("after idle {ruby_callback #{cb_id}}")
      after_id.instance_variable_set(:@cb_id, cb_id)
      after_id
    end

    # Schedule a repeating timer. Calls the block every +ms+ milliseconds
    # until cancelled. The block runs on the main thread in the event loop,
    # so it must be fast (don't block the UI).
    #
    # @param ms [Integer] interval in milliseconds
    # @param on_error [:raise, Proc, nil] error handling strategy:
    #   - +:raise+ (default) — cancels the timer and raises the exception
    #     from the next call to {#update}.
    #   - +Proc+ — called with the exception; timer keeps running.
    #   - +nil+ — cancels the timer silently; error stored in {RepeatingTimer#last_error}.
    # @yield block to call on each tick
    # @return [RepeatingTimer] cancel handle
    #
    # @example Basic polling loop
    #   timer = app.every(50) { update_display }
    #   timer.cancel  # stop later
    #
    # @example With error handler (timer keeps running)
    #   timer = app.every(100, on_error: ->(e) { log(e) }) { risky_work }
    #
    # @example Silent cancel on error
    #   timer = app.every(50, on_error: nil) { maybe_fails }
    #   timer.last_error  # => check later
    def every(ms, on_error: :raise, &block)
      RepeatingTimer.new(self, ms, on_error: on_error, &block)
    end

    # Cancel a pending {#after} or {#after_idle} timer.
    # @param after_id [String] timer ID returned by {#after} or {#after_idle}
    # @return [void]
    # @see https://www.tcl-lang.org/man/tcl8.6/TclCmd/after.htm#M7 after cancel
    def after_cancel(after_id)
      @interp.tcl_eval("after cancel #{after_id}")
      if (cb_id = after_id.instance_variable_get(:@cb_id))
        @interp.unregister_callback(cb_id)
        after_id.instance_variable_set(:@cb_id, nil)
      end
      after_id
    end

    # Split a Tcl list string into a Ruby array of strings.
    # @param str [String] a Tcl-formatted list
    # @return [Array<String>]
    def split_list(str)
      Teek.split_list(str)
    end

    # Build a properly-escaped Tcl list from Ruby strings.
    # @param args [Array<String>] elements to join
    # @return [String] a Tcl-formatted list
    def make_list(*args)
      Teek.make_list(*args)
    end

    # Convert a Tcl boolean string ("0", "1", "yes", "no", etc.) to Ruby boolean.
    # @param str [String] a Tcl boolean value
    # @return [Boolean]
    def tcl_to_bool(str)
      Teek.tcl_to_bool(str)
    end

    # Convert a Ruby boolean to a Tcl boolean string ("1" or "0").
    # @param val [Boolean]
    # @return [String] "1" or "0"
    def bool_to_tcl(val)
      Teek.bool_to_tcl(val)
    end

    # Tk menu entry types that take a `-command` option, for the
    # unmanaged-menu-callback warning in {#command}.
    MENU_ENTRY_TYPES = %w[command cascade checkbutton radiobutton separator].freeze
    private_constant :MENU_ENTRY_TYPES

    # Build and evaluate a Tcl command from Ruby values.
    # Positional args are converted: Symbols pass bare, Procs become
    # callbacks, everything else is brace-quoted. Keyword args become
    # +-key value+ option pairs.
    # @example
    #   app.command(:pack, '.btn', side: :left, padx: 10)
    #   # evaluates: pack .btn -side left -padx {10}
    #
    # @note This is a dumb, general-purpose Tcl builder - it does not
    #   understand menus. Passing a `command:` Proc to a menu's `add`,
    #   `insert`, or `entryconfigure` here registers a real, working
    #   callback, but nothing ever releases it if the entry is later
    #   replaced or the menu is rebuilt in place. teek warns (once per
    #   path) when it recognizes this shape; use {#menu} instead, which
    #   tracks and releases these automatically.
    # @param cmd [Symbol, String] the Tcl command name
    # @param args positional arguments
    # @param kwargs keyword arguments mapped to +-key value+ pairs
    # @return [String] the Tcl result
    def command(cmd, *args, **kwargs)
      warn_if_unmanaged_menu_command(cmd, args, kwargs)
      warn_if_unmanaged_tag_bind(cmd, args)

      parts = [cmd.to_s]
      i = 0
      while i < args.length
        arg = args[i]
        if arg.is_a?(Proc)
          id = register_callback(arg)
          subs = []
          while i + 1 < args.length && args[i + 1].is_a?(String) && args[i + 1].start_with?('%')
            subs << args[i + 1]
            i += 1
          end
          parts << if subs.empty?
                     "{ruby_callback #{id}}"
                   else
                     "{ruby_callback #{id} #{subs.join(' ')}}"
                   end
        else
          parts << tcl_value(arg)
        end
        i += 1
      end
      kwargs.each do |key, value|
        parts << "-#{key}"
        parts << tcl_value(value)
      end
      @interp.tcl_eval(parts.join(' '))
    end

    # Register any Proc-valued kwarg (e.g. command:, validatecommand:) as a
    # callback tracked under +path+, releasing it if reconfigured or when
    # the widget is destroyed. The tracked-callback equivalent of {#bind}
    # for widget-level options instead of event bindings - a widget's own
    # options are never silently renumbered or invalidated out from under
    # us the way menu entries are, so this reuses bind's cheap in-memory
    # {CallbackRegistry#reconcile} style rather than menu's live-scan one.
    #
    # Called by {#create_widget} and {Widget#command}, which both know
    # +path+ unambiguously; not meant to be called directly. Building a Tcl
    # command via the raw {#command} with a widget path you construct
    # yourself does not go through this - see {#command}'s note.
    # @param path [String] the widget path these kwargs configure
    # @param kwargs [Hash] keyword arguments about to be passed to {#command}
    # @return [Hash] +kwargs+ with any Proc values swapped for the Tcl
    #   script {#command} embeds
    def track_widget_option_callbacks(path, kwargs)
      proc_kwargs = kwargs.select { |_, value| value.is_a?(Proc) }
      return kwargs if proc_kwargs.empty?

      ids = proc_kwargs.transform_values { |value| register_callback(value, relay_break_continue: false) }
      @callback_registry.reconcile([:widget_option, path]) { |before| before.merge(ids) }
      kwargs.merge(ids.transform_values { |id| "ruby_callback #{id}" })
    end

    # Create a Tk widget and return a {Widget} wrapper.
    #
    # Auto-generates a unique path if none is given. The path is derived from
    # the widget type and a monotonic counter.
    #
    # @param type [String, Symbol] Tk widget command (e.g. 'ttk::button', :canvas)
    # @param path [String, nil] explicit Tk path, or nil for auto-naming
    # @param parent [Widget, String, nil] parent widget for path nesting
    # @param idempotent [Boolean] skip the creation command if a widget
    #   already exists at +path+ - for widgets meant to be fetched by a
    #   stable, caller-chosen path and reused across many calls (see {#menu})
    #   rather than freshly created each time
    # @param kwargs keyword arguments passed to the Tk widget command
    # @return [Widget] the created widget, extended with whatever behavior
    #   module is registered for +type+ (see {Widget.register_behavior})
    #
    # @example Auto-named
    #   btn = app.create_widget('ttk::button', text: 'Click')
    #   # btn.path => ".ttkbtn1"
    #
    # @example Explicit path
    #   frm = app.create_widget('ttk::frame', '.myframe')
    #
    # @example Nested under a parent
    #   frm = app.create_widget('ttk::frame')
    #   btn = app.create_widget('ttk::button', parent: frm, text: 'Click')
    #   # btn.path => ".ttkfrm1.ttkbtn1"
    #
    def create_widget(type, path = nil, parent: nil, idempotent: false, **kwargs)
      type_s = type.to_s
      path ||= next_widget_path(type_s, parent)
      unless idempotent && tcl_eval("winfo exists #{path}") == '1'
        command(type_s, path, **track_widget_option_callbacks(path, kwargs))
      end
      widget = Widget.new(self, path)
      behavior = Widget.behavior_for(type_s)
      widget.extend(behavior) if behavior
      widget
    end

    # Wrap a Tk menu at the given path, creating it (tearoff disabled) if
    # it doesn't exist yet. Safe to call repeatedly with the same path -
    # it's a flyweight, not a handle you need to hold onto: call this again
    # any time you're about to rebuild the menu (e.g. on every right-click).
    # @param path [String] Tk menu path (e.g. ".card.ctx")
    # @param kwargs extra options for the underlying `menu` command, used
    #   only the first time this path is created
    # @return [Widget] extended with menu entry methods (add_command, delete, ...)
    # @see MenuBehavior
    def menu(path, **kwargs)
      create_widget(:menu, path, idempotent: true, tearoff: 0, **kwargs)
    end

    # Add a directory to Tcl's package search path.
    # @param path [String] directory containing Tcl packages
    # @return [void]
    def add_package_path(path)
      tcl_eval("lappend ::auto_path {#{path}}")
    end

    # Load a Tcl package into this interpreter.
    # @param name [String] package name (e.g. "BWidget")
    # @param version [String, nil] minimum version constraint
    # @return [String] the version that was loaded
    # @raise [Teek::TclError] if the package is not found
    # @see https://www.tcl-lang.org/man/tcl8.6/TclCmd/package.htm#M10 package require
    def require_package(name, version = nil)
      cmd = version ? "package require #{name} #{version}" : "package require #{name}"
      tcl_eval(cmd)
    rescue Teek::TclError => e
      raise Teek::TclError, "Package '#{name}' not found. Ensure it is installed and on Tcl's auto_path. (#{e.message})"
    end

    # List all packages known to this interpreter.
    # Scans +auto_path+ for package indexes before querying.
    # @return [Array<String>]
    # @see https://www.tcl-lang.org/man/tcl8.6/TclCmd/package.htm#M7 package names
    def package_names
      scan_packages
      split_list(tcl_eval('package names'))
    end

    # Check if a package is already loaded in this interpreter.
    # @param name [String] package name
    # @return [Boolean]
    # @see https://www.tcl-lang.org/man/tcl8.6/TclCmd/package.htm#M8 package present
    def package_present?(name)
      tcl_eval("package present #{name}")
      true
    rescue Teek::TclError
      false
    end

    # List available versions of a package.
    # Scans +auto_path+ for package indexes before querying.
    # @param name [String] package name
    # @return [Array<String>]
    # @see https://www.tcl-lang.org/man/tcl8.6/TclCmd/package.htm#M14 package versions
    def package_versions(name)
      scan_packages
      split_list(tcl_eval("package versions #{name}"))
    end

    # Set a Tcl variable. Useful for widget +textvariable+ and +variable+ options.
    # Goes through Tcl_SetVar directly (no re-parsing), so the value never
    # needs escaping - braces, backslashes, +$+, +[+, whatever, all safe.
    # @param name [String] variable name (array-element and namespaced forms work)
    # @param value [String] value to set
    # @return [String] the value
    # @see https://www.tcl-lang.org/man/tcl8.6/TclCmd/set.htm set
    def set_variable(name, value)
      @interp.tcl_set_var(name.to_s, value.to_s)
    end

    # Get a Tcl variable's value.
    # @param name [String] variable name (array-element and namespaced forms work)
    # @return [String] the value
    # @raise [Teek::TclError] if the variable doesn't exist
    # @see https://www.tcl-lang.org/man/tcl8.6/TclCmd/set.htm set
    def get_variable(name)
      value = @interp.tcl_get_var(name.to_s)
      return value unless value.nil?
      raise Teek::TclError, "can't read \"#{name}\": no such variable"
    end

    # Destroy a widget and all its children.
    # @param widget [String] Tk widget path (e.g. ".frame1")
    # @return [void]
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/destroy.htm destroy
    def destroy(widget = '.')
      raise ArgumentError, 'widget path cannot be nil' if widget.nil?
      tcl_eval("destroy #{widget}")
    end

    # Measure the pixel width of a text string in a given font.
    # Uses Tk's C font API directly — faster than the Tcl +font measure+ command.
    # @param font [String] font description (e.g. "Helvetica 12", "TkDefaultFont")
    # @param text [String] text to measure
    # @return [Integer] pixel width
    # @raise [Teek::TclError] if the font is not found
    # @see https://www.tcl-lang.org/man/tcl8.6/TkLib/MeasureChar.htm Tk_TextWidth
    def text_width(font, text)
      @interp.text_width(font, text)
    end

    # Get font metrics (ascent, descent, linespace) for a given font.
    # Uses Tk's C font API directly.
    # @param font [String] font description (e.g. "Helvetica 12", "TkDefaultFont")
    # @return [Hash{Symbol => Integer}] +:ascent+, +:descent+, +:linespace+
    # @raise [Teek::TclError] if the font is not found
    # @see https://www.tcl-lang.org/man/tcl8.6/TkLib/FontId.htm Tk_GetFontMetrics
    def font_metrics(font)
      @interp.font_metrics(font)
    end

    # Measure how many bytes of text fit within a pixel width limit.
    # Useful for text truncation, ellipsis, and line wrapping.
    # @param font [String] font description (e.g. "Helvetica 12")
    # @param text [String] text to measure
    # @param max_pixels [Integer] maximum pixel width (-1 for unlimited)
    # @param opts [Hash] options
    # @option opts [Boolean] :partial_ok allow partial character at boundary
    # @option opts [Boolean] :whole_words break only at word boundaries
    # @option opts [Boolean] :at_least_one always return at least one character
    # @return [Hash{Symbol => Integer}] +:bytes+ and +:width+
    # @raise [Teek::TclError] if the font is not found
    # @see https://www.tcl-lang.org/man/tcl8.6/TkLib/MeasureChar.htm Tk_MeasureChars
    def measure_chars(font, text, max_pixels, **opts)
      @interp.measure_chars(font, text, max_pixels, opts)
    end

    # Show a busy cursor on a window while executing a block.
    # The cursor is restored even if the block raises.
    # @param window [String] Tk window path
    # @yield the work to perform while busy
    # @return the block's return value
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/busy.htm tk busy
    def busy(window: '.')
      tcl_eval("tk busy hold #{window}")
      tcl_eval('update idletasks')
      yield
    ensure
      tcl_eval("tk busy forget #{window}")
    end

    # Enter the Tk event loop. Blocks until the application exits.
    # @return [void]
    # @see https://www.tcl-lang.org/man/tcl8.6/TkLib/MainLoop.htm Tk_MainLoop
    def mainloop
      if defined?(IRB) || defined?(Pry) || $0 == 'irb' || $0 == 'pry'
        warn "Teek: mainloop blocks the current thread and will make your REPL unresponsive.\n" \
             "  Instead, use app.update in a loop or call app.update manually between commands:\n" \
             "    app.show\n" \
             "    app.update          # process pending events\n" \
             "    # ... interact with your app ...\n" \
             "    app.update          # process again after changes"
      end
      @interp.mainloop
    end

    # Process all pending events and idle callbacks, then return.
    # @return [void]
    # @see https://www.tcl-lang.org/man/tcl8.6/TclCmd/update.htm update
    def update
      @interp.tcl_eval('update')
      if (e = @_pending_exception)
        @_pending_exception = nil
        raise e
      end
    end

    # Process only pending idle callbacks (e.g. geometry redraws), then return.
    # @return [void]
    # @see https://www.tcl-lang.org/man/tcl8.6/TclCmd/update.htm update idletasks
    def update_idletasks
      @interp.tcl_eval('update idletasks')
    end

    # Show a window. Defaults to the root window (".").
    # @param window [String] Tk window path
    # @return [void]
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/wm.htm#M38 wm deiconify
    def show(window = '.')
      @interp.tcl_eval("wm deiconify #{window}")
    end

    # Hide a window without destroying it. Defaults to the root window (".").
    # @param window [String] Tk window path
    # @return [void]
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/wm.htm#M65 wm withdraw
    def hide(window = '.')
      @interp.tcl_eval("wm withdraw #{window}")
    end

    # Enable the Tk debug console. The console starts hidden and can be
    # toggled with the given keyboard shortcut (default: F12).
    #
    # The Tk console is a built-in interactive Tcl shell — useful for
    # inspecting variables, running Tcl commands, and debugging widget
    # layouts at runtime. It is available on macOS and Windows only;
    # on Linux this method is a no-op (Linux has the real terminal).
    #
    # @param keybinding [String] Tk event to toggle the console
    #   (default: "<F12>")
    # @return [Boolean] true if the console was created, false if
    #   unavailable on this platform
    # @example
    #   app = Teek::App.new
    #   app.add_debug_console            # F12 toggles console
    #   app.add_debug_console("<F11>")   # custom key
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/console.htm console
    def add_debug_console(keybinding = '<F12>')
      @interp.create_console
      @_console_visible = false

      toggle = proc do |*|
        if @_console_visible
          tcl_eval('console hide')
          @_console_visible = false
        else
          tcl_eval('console show')
          @_console_visible = true
        end
      end

      command(:bind, '.', keybinding, toggle)
      true
    rescue TclError => e
      warn "Teek: debug console not available on this platform (#{e.message})"
      false
    end

    # Set a window's title.
    # @param title [String] new title
    # @param window [String] Tk window path
    # @return [String] the title
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/wm.htm#M63 wm title
    def set_window_title(title, window: '.')
      tcl_eval("wm title #{window} {#{title}}")
    end

    # Get a window's current title.
    # @param window [String] Tk window path
    # @return [String] current title
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/wm.htm#M63 wm title
    def window_title(window: '.')
      tcl_eval("wm title #{window}")
    end

    # Set a window's geometry (e.g. "400x300", "400x300+100+50").
    # @param geometry [String] geometry string
    # @param window [String] Tk window path
    # @return [String] the geometry
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/wm.htm#M42 wm geometry
    def set_window_geometry(geometry, window: '.')
      tcl_eval("wm geometry #{window} #{geometry}")
    end

    # Get a window's current geometry.
    # @param window [String] Tk window path
    # @return [String] geometry string (e.g. "400x300+0+0")
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/wm.htm#M42 wm geometry
    def window_geometry(window: '.')
      tcl_eval("wm geometry #{window}")
    end

    # Set whether a window is resizable.
    # @param width [Boolean] allow horizontal resize
    # @param height [Boolean] allow vertical resize
    # @param window [String] Tk window path
    # @return [void]
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/wm.htm#M59 wm resizable
    def set_window_resizable(width, height, window: '.')
      tcl_eval("wm resizable #{window} #{width ? 1 : 0} #{height ? 1 : 0}")
    end

    # Get whether a window is resizable.
    # @param window [String] Tk window path
    # @return [Array(Boolean, Boolean)] [width_resizable, height_resizable]
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/wm.htm#M59 wm resizable
    def window_resizable(window: '.')
      parts = tcl_eval("wm resizable #{window}").split
      [parts[0] == '1', parts[1] == '1']
    end

    # Bind a Tk event on a widget, with optional substitutions forwarded
    # as block arguments. Substitutions can be symbols (mapped via
    # {BIND_SUBS}) or raw Tcl +%+ codes passed through as-is.
    #
    # @example Mouse click with window coordinates
    #   app.bind('.c', 'Button-1', :x, :y) { |x, y| puts "#{x},#{y}" }
    # @example Key press
    #   app.bind('.', 'KeyPress', :keysym) { |k| puts k }
    # @example No substitutions
    #   app.bind('.btn', 'Enter') { highlight }
    # @example Raw Tcl expression (for codes not in BIND_SUBS)
    #   app.bind('.c', 'Button-1', '%T') { |type| ... }
    # @example Canvas coordinate conversion
    #   app.bind(canvas, 'Button-1', :x, :y) do |x, y|
    #     cx = app.command(canvas, :canvasx, x).to_f
    #     cy = app.command(canvas, :canvasy, y).to_f
    #   end
    #
    # @note Each substitution crosses from Tcl to Ruby once. Any {#command}
    #   calls inside the block are additional round-trips. This is negligible
    #   for click/key events but could matter for hot-path handlers like
    #   +<Motion>+ that fire hundreds of times per second. For those, consider
    #   {#tcl_eval} with inline Tcl expressions to do all work in one evaluation.
    #
    # @param widget [String] Tk widget path or class tag (e.g. ".btn", "Entry")
    # @param event [String] Tk event name, with or without angle brackets
    # @param subs [Array<Symbol, String>] substitution codes (see {BIND_SUBS})
    # @yield [*values] called when the event fires, with substitution values
    # @return [void]
    # @see #unbind
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/bind.htm bind
    #
    BIND_SUBS = {
      x: '%x', y: '%y',                   # window coordinates
      root_x: '%X', root_y: '%Y',         # screen coordinates
      widget: '%W',                        # widget path
      keysym: '%K', keycode: '%k',         # key events
      char: '%A',                          # character (key events)
      width: '%w', height: '%h',           # Configure events
      button: '%b',                        # mouse button number
      mouse_wheel: '%D',                   # mousewheel delta
      type: '%T',                          # event type
      data: '%d',                          # virtual event data (Tk 8.6+)
    }.freeze

    def bind(widget, event, *subs, &block)
      event_str = event.start_with?('<') ? event : "<#{event}>"
      cb = register_callback(proc { |*args| block.call(*args) })
      @callback_registry.reconcile([:bind, widget]) { |before| before.merge(event_str => cb) }
      tcl_subs = subs.map { |s| s.is_a?(Symbol) ? BIND_SUBS.fetch(s) : s.to_s }
      sub_str = tcl_subs.empty? ? '' : ' ' + tcl_subs.join(' ')
      @interp.tcl_eval("bind #{widget} #{event_str} {ruby_callback #{cb}#{sub_str}}")
    end

    # Remove an event binding previously set with {#bind}.
    # @param widget [String] Tk widget path or class tag
    # @param event [String] Tk event name, with or without angle brackets
    # @return [void]
    # @see #bind
    # @see https://www.tcl-lang.org/man/tcl8.6/TkCmd/bind.htm bind
    def unbind(widget, event)
      event_str = event.start_with?('<') ? event : "<#{event}>"
      @callback_registry.reconcile([:bind, widget]) { |before| before.reject { |k, _| k == event_str } }
      @interp.tcl_eval("bind #{widget} #{event_str} {}")
    end

    # Register a widget as a file drop target.
    # After registration, dropping files onto the widget generates a single
    # +<<DropFile>>+ virtual event with all file paths as a Tcl list in the
    # event data. Use {#split_list} to convert to a Ruby array.
    # @param widget [String] Tk widget path (e.g., ".", ".frame")
    # @return [void]
    # @example
    #   app.register_drop_target('.')
    #   app.bind('.', '<<DropFile>>', :data) do |data|
    #     paths = app.split_list(data)
    #     puts "Dropped #{paths.length} file(s): #{paths.inspect}"
    #   end
    def register_drop_target(widget)
      @interp.register_drop_target(widget.to_s)
    end

    # Get the macOS window appearance. No-op (returns +nil+) on non-macOS.
    # @example
    #   app.appearance          # => "aqua", "darkaqua", or "auto"
    #   app.appearance = :light # force light mode
    #   app.appearance = :dark  # force dark mode
    #   app.appearance = :auto  # follow system setting
    # @return [String, nil] "aqua", "darkaqua", "auto", or nil on non-macOS
    # @see #dark?
    def appearance
      return nil unless aqua?
      if tk_major >= 9
        @interp.tcl_eval('wm attributes . -appearance').delete('"')
      else
        @interp.tcl_eval('tk::unsupported::MacWindowStyle appearance .')
      end
    end

    # Set the macOS window appearance. No-op on non-macOS.
    # @param mode [Symbol, String] +:light+, +:dark+, +:auto+, or a raw Tk value
    # @return [void]
    def appearance=(mode)
      return unless aqua?
      value = case mode.to_sym
              when :light then 'aqua'
              when :dark  then 'darkaqua'
              when :auto  then 'auto'
              else mode.to_s
              end
      if tk_major >= 9
        @interp.tcl_eval("wm attributes . -appearance #{value}")
      else
        @interp.tcl_eval("tk::unsupported::MacWindowStyle appearance . #{value}")
      end
    end

    # Returns true if the window is currently displayed in dark mode.
    # Always returns false on non-macOS.
    # @return [Boolean]
    def dark?
      return false unless aqua?
      @interp.tcl_eval('tk::unsupported::MacWindowStyle isdark .').delete('"') == '1'
    end

    private

    # Short prefixes for common Tk widget types.
    # The base name (after the last ::) is looked up here; the namespace
    # prefix (e.g. "ttk") is prepended verbatim.  Unmapped types fall
    # back to the full lowercased name with colons stripped.
    WIDGET_PREFIXES = {
      'button'      => 'btn',
      'label'       => 'lbl',
      'entry'       => 'ent',
      'frame'       => 'frm',
      'text'        => 'txt',
      'canvas'      => 'cvs',
      'scrollbar'   => 'sb',
      'scale'       => 'scl',
      'checkbutton' => 'chk',
      'radiobutton' => 'rad',
      'combobox'    => 'cbx',
      'labelframe'  => 'lfrm',
      'treeview'    => 'tv',
      'notebook'    => 'nb',
      'progressbar' => 'pbar',
      'separator'   => 'sep',
      'spinbox'     => 'spn',
      'panedwindow' => 'pw',
      'toplevel'    => 'top',
      'menubutton'  => 'mbtn',
      'sizegrip'    => 'sg',
    }.freeze
    private_constant :WIDGET_PREFIXES

    def next_widget_path(type, parent)
      prefix = widget_prefix(type)
      @widget_counters[prefix] += 1
      parent_path = parent ? parent.to_s : ''
      if parent_path.empty? || parent_path == '.'
        ".#{prefix}#{@widget_counters[prefix]}"
      else
        "#{parent_path}.#{prefix}#{@widget_counters[prefix]}"
      end
    end

    def widget_prefix(type)
      parts = type.downcase.split('::')
      base = parts.pop
      ns = parts.join
      short = WIDGET_PREFIXES[base] || base
      "#{ns}#{short}"
    end

    # Force Tcl to scan auto_path for pkgIndex.tcl files so that
    # package_names and package_versions reflect all discoverable packages.
    def scan_packages
      tcl_eval('catch {package require __teek_scan__}')
    end

    def aqua?
      @aqua ||= @interp.tcl_eval('tk windowingsystem') == 'aqua'
    end

    def tk_major
      @tk_major ||= @interp.tcl_eval('info patchlevel').split('.').first.to_i
    end

    def setup_widget_tracking
      @create_cb_id = @interp.register_callback(proc { |path, cls|
        next if path.start_with?('.teek_debug')
        @widgets[path] = { class: cls, parent: File.dirname(path).gsub(/\A$/, '.') }
        @debugger&.on_widget_created(path, cls)
      })

      # Tcl proc called on widget creation (trace leave)
      @interp.tcl_eval("proc ::teek_track_create {cmd_string code result op} {
        set path [lindex $cmd_string 1]
        if {$code == 0 && [winfo exists $path]} {
          set cls [winfo class $path]
          ruby_callback #{@create_cb_id} $path $cls
        }
      }")

      # Add trace on each widget command
      Teek::WIDGET_COMMANDS.each do |cmd|
        @interp.tcl_eval("catch {trace add execution #{cmd} leave ::teek_track_create}")
      end
    end

    # Installed unconditionally (unlike widget-creation tracking, which is
    # opt-out via track_widgets: false) so that bind-callback cleanup always
    # runs. A single `bind all <Destroy>` script is used because Tcl's bind
    # command replaces rather than appends per tag+event, so widget-tracking
    # cleanup is folded into the same callback rather than installed separately.
    def setup_destroy_cleanup
      @destroy_cb_id = @interp.register_callback(proc { |path|
        @callback_registry.forget_all_for_path(path)
        next if path.start_with?('.teek_debug')
        if @track_widgets
          @widgets.delete(path)
          @debugger&.on_widget_destroyed(path)
        end
      })
      @interp.tcl_eval("bind all <Destroy> {ruby_callback #{@destroy_cb_id} %W}")
    end

    # Diagnostic only - registers nothing, tracks nothing, changes no
    # behavior. Recognizes a `-command` Proc being attached to a menu entry
    # through the raw command() path (bypassing #menu) and warns once per
    # path, since that Proc will leak the moment this entry is replaced or
    # the menu is rebuilt.
    def warn_if_unmanaged_menu_command(path, args, kwargs)
      return unless kwargs[:command].is_a?(Proc)
      return if @menu_command_warned[path]

      sub = args[0].to_s
      looks_like_menu_entry =
        case sub
        when 'add' then MENU_ENTRY_TYPES.include?(args[1].to_s)
        when 'insert' then MENU_ENTRY_TYPES.include?(args[2].to_s)
        when 'entryconfigure' then true
        else false
        end
      return unless looks_like_menu_entry

      @menu_command_warned[path] = true
      warn "teek: command: proc passed to app.command(#{path.inspect}, :#{sub}, ...) is not " \
           "tracked and will leak if this entry is replaced or the menu is rebuilt in place. " \
           "Use app.menu(#{path.inspect}) instead - it releases these automatically."
    end

    # Diagnostic only - same rationale as {#warn_if_unmanaged_menu_command}.
    # Recognizes a Proc being attached to a `tag bind` call through the raw
    # command() path (bypassing a widget's #tag_bind) and warns once per
    # path.
    def warn_if_unmanaged_tag_bind(path, args)
      return if @tag_bind_warned[path]
      return unless args[0].to_s == 'tag' && args[1].to_s == 'bind'
      return unless args.any? { |a| a.is_a?(Proc) }

      @tag_bind_warned[path] = true
      warn "teek: a Proc passed to app.command(#{path.inspect}, :tag, :bind, ...) is not " \
           "tracked and will leak if this tag binding is replaced or the tag is deleted. " \
           "Use the widget's #tag_bind instead - it releases these automatically."
    end

    def tcl_value(value)
      case value
      when Proc
        # A Proc reaching tcl_value is always a kwarg/option value (e.g.
        # -command), never a bind script - see #register_callback's note
        # on why break/continue can't be relayed there.
        id = register_callback(value, relay_break_continue: false)
        "{ruby_callback #{id}}"
      when Symbol
        value.to_s
      when Array
        "{#{value.map { |v| tcl_value(v) }.join(' ')}}"
      else
        tcl_quote_string(value.to_s)
      end
    end

    # Brace-quote a string for Tcl, falling back to double-quote quoting
    # when the string ends with a backslash (Tcl treats \} as an escaped
    # brace, preventing the closing brace from terminating the group).
    def tcl_quote_string(s)
      if s.end_with?('\\')
        '"' + s.gsub(/[\\\[\]$"]/) { |c| "\\#{c}" } + '"'
      else
        "{#{s}}"
      end
    end
  end

  # A cancellable repeating timer that fires on the main thread.
  #
  # Created via {App#every}. Reschedules itself after each tick using
  # Tcl's +after+ command. The block runs in the event loop, so it
  # must complete quickly to avoid blocking the UI.
  #
  # Tracks timing drift: if a tick fires significantly late (more than
  # 2x the interval), a warning is printed to stderr. This helps catch
  # blocks that are too slow for the requested interval.
  #
  # @see App#every
  class RepeatingTimer
    # @return [Integer] interval in milliseconds
    attr_reader :interval

    # @return [Exception, nil] the last error if the timer stopped due to an
    #   unhandled exception, nil otherwise
    attr_reader :last_error

    # @return [Integer] number of ticks that fired late (> 2x interval)
    attr_reader :late_ticks

    # @api private
    def initialize(app, ms, on_error: nil, &block)
      raise ArgumentError, "interval must be positive, got #{ms}" if ms <= 0

      @app = app
      @interval = ms
      @block = block
      @on_error = on_error
      @cancelled = false
      @after_id = nil
      @last_error = nil
      @late_ticks = 0
      @next_expected = nil
      schedule
    end

    # Stop the timer. Safe to call multiple times.
    # @return [void]
    def cancel
      return if @cancelled
      @cancelled = true
      @app.after_cancel(@after_id) if @after_id
      @after_id = nil
    end

    # @return [Boolean] true if the timer has been cancelled
    def cancelled?
      @cancelled
    end

    # Change the interval. Takes effect on the next tick.
    # @param ms [Integer] new interval in milliseconds
    def interval=(ms)
      raise ArgumentError, "interval must be positive, got #{ms}" if ms <= 0
      @interval = ms
    end

    private

    def schedule
      return if @cancelled
      @next_expected = now_ms + @interval
      @after_id = @app.after(@interval) { tick }
    end

    def tick
      return if @cancelled
      check_drift
      @block.call
      schedule
    rescue => e
      @last_error = e
      case @on_error
      when :raise
        @cancelled = true
        # Store on App so it raises from the next app.update call.
        # Don't re-raise here — that would go through rb_protect → bgerror.
        @app._pending_exception = e
      when Proc
        begin
          @on_error.call(e)
        rescue => handler_err
          @last_error = handler_err
          @cancelled = true
          @app._pending_exception = handler_err
          return
        end
        schedule
      when nil
        @cancelled = true
      end
    end

    def check_drift
      return unless @next_expected
      actual = now_ms
      drift = actual - @next_expected
      if drift > @interval
        @late_ticks += 1
        warn "Teek::RepeatingTimer: tick #{@late_ticks} fired #{drift.round}ms late " \
             "(interval=#{@interval}ms)"
      end
    end

    def now_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    end
  end
end
