# frozen_string_literal: true

module Teek
  # Thin wrapper around a Tk widget path. Holds a reference to the App and
  # the widget's Tcl path string.
  #
  # Instances are interchangeable with plain strings anywhere a widget path
  # is expected thanks to {#to_s} returning the path.
  #
  # Created via {App#create_widget}:
  #
  # @example
  #   btn = app.create_widget('ttk::button', text: 'Click')
  #   btn.command(:configure, text: 'Updated')
  #   app.command(:pack, btn, pady: 10)  # to_s makes this work
  #   btn.destroy
  #
  # @see App#create_widget
  class Widget
    attr_reader :app, :path

    def initialize(app, path)
      @app = app
      @path = path
    end

    # @return [String] the Tcl widget path
    def to_s
      @path
    end

    # Invoke a widget subcommand. Prepends the widget path as the Tcl command.
    #
    # @example
    #   btn.command(:configure, text: 'New')  # => .ttkbutton1 configure -text {New}
    #   btn.command(:invoke)                  # => .ttkbutton1 invoke
    #
    # @param args positional arguments
    # @param kwargs keyword arguments mapped to -key value pairs; any Proc
    #   value (e.g. command:) is tracked and released if reconfigured or
    #   when this widget is destroyed
    # @return [String] the Tcl result
    def command(*args, **kwargs)
      @app.command(@path, *args, **kwargs)
    end

    # Destroy this widget and all its children.
    # @return [void]
    def destroy
      @app.destroy(@path)
    end

    # Check if this widget still exists in the Tk interpreter.
    # @return [Boolean]
    def exist?
      @app.winfo.exists?(@path)
    end

    # @return [Integer] current width in pixels
    # @see Winfo#width
    def width
      @app.winfo.width(@path)
    end

    # @return [Integer] current height in pixels
    # @see Winfo#height
    def height
      @app.winfo.height(@path)
    end

    # Pack this widget.
    # @param kwargs options passed to the Tk pack command
    # @return [self]
    def pack(**kwargs)
      @app.command(:pack, @path, **kwargs)
      self
    end

    # Grid this widget.
    # @param kwargs options passed to the Tk grid command
    # @return [self]
    def grid(**kwargs)
      @app.command(:grid, @path, **kwargs)
      self
    end

    # Bind an event on this widget.
    # @param event [String] Tk event name
    # @param subs [Array<Symbol, String>] substitution codes
    # @yield called when the event fires
    # @return [void]
    # @see App#bind
    def bind(event, *subs, &block)
      @app.bind(@path, event, *subs, &block)
    end

    # Remove an event binding from this widget.
    # @param event [String] Tk event name
    # @return [void]
    # @see App#unbind
    def unbind(event)
      @app.unbind(@path, event)
    end

    # This widget as a {Window} - the window-scoped counterpart covering
    # `wm` subcommands and composite behaviors (on_close, grab_set/
    # grab_release, modal). Meant for toplevels.
    # @return [Window]
    def window
      @app.window(@path)
    end

    # Register a handler for this window's close button (WM_DELETE_WINDOW).
    # Meant for toplevels; see {Window#on_close} for the full behavior.
    # @yield called when the window's close button is pressed
    # @return [void]
    # @see Window#on_close
    def on_close(&block)
      window.on_close(&block)
    end

    # Grab input on this window. See {Window#grab_set}.
    # @param global [Boolean]
    # @return [void]
    def grab_set(global: false)
      window.grab_set(global: global)
    end

    # Release a grab previously set on this window. See {Window#grab_release}.
    # @return [void]
    def grab_release
      window.grab_release
    end

    # Make this window modal. See {Window#modal}.
    # @param global [Boolean]
    # @yield optional - runs with the grab and focus already set
    # @return [void]
    def modal(global: false, &block)
      window.modal(global: global, &block)
    end

    def inspect
      "#<Teek::Widget #{@path}>"
    end

    def ==(other)
      other.is_a?(Widget) ? @path == other.path : @path == other.to_s
    end
    alias eql? ==

    def hash
      @path.hash
    end
  end
end
