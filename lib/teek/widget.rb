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
    class << self
      # Associate a Tk widget-command type string (e.g. "menu") with a
      # module of extra instance methods. {App#create_widget} extends a
      # plain Widget with whichever module is registered for the type
      # being created, so widget-type-specific behavior (menu's entry
      # methods, for example) lives in its own module rather than in
      # Widget itself or in a subclass.
      #
      # Call this from the file that defines the behavior module - it's
      # how that module makes itself known, without App or Widget having
      # to be edited for each new widget type. This is also the hook for
      # third-party or application-specific widget behaviors: define a
      # module and register it for your own type string.
      #
      # @param type [String, Symbol] Tk widget-command type string
      # @param behavior_module [Module] extended onto matching Widget instances
      # @return [void]
      def register_behavior(type, behavior_module)
        behaviors[type.to_s] = behavior_module
      end

      # @param type [String, Symbol] Tk widget-command type string
      # @return [Module, nil] the module registered for +type+, if any
      def behavior_for(type)
        behaviors[type.to_s]
      end

      private

      def behaviors
        @behaviors ||= {}
      end
    end

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
    # @param kwargs keyword arguments mapped to -key value pairs
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
      @app.tcl_eval("winfo exists #{@path}") == '1'
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
