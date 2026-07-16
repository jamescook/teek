# frozen_string_literal: true

require_relative 'errors'

module Teek
  module UI
    # A reactive Tcl variable, wrapped for Ruby - Tk's own native
    # -textvariable/-variable machinery, done properly instead of the
    # hand-rolled "VAR_NAME constant + manual set_variable/get_variable"
    # pattern this replaces. Widgets bound to the same Var stay in sync with
    # each other for free (that part is entirely Tk's doing); this class
    # adds typed Ruby access and an on_change callback on top.
    #
    # Its Tcl variable name is allocated at build time (see {WidgetDSL#var})
    # - a plain string, no interpreter needed - so widgets can capture it as
    # a `-variable`/`-textvariable` option before realize even happens. The
    # variable itself, its initial value, and its change trace only become
    # real at #realize.
    class Var
      # @return [String] the Tcl variable name
      attr_reader :name

      # @api private
      def initialize(name, initial)
        @name = name
        @initial = initial
        @on_change_callbacks = []
        @app = nil
      end

      # The current value, coerced to match the initial value's type
      # (Integer/Float/Boolean pass through typed; anything else is a String).
      # @raise [NotRealizedError] before realize
      def value
        raise_unless_realized!
        coerce(@app.get_variable(@name))
      end

      # @raise [NotRealizedError] before realize
      def value=(new_value)
        raise_unless_realized!
        @app.set_variable(@name, to_tcl(new_value))
      end

      # Register a callback fired whenever the value changes, regardless of
      # whether Ruby (#value=) or a bound widget caused it. Queues
      # regardless of build/realize phase - there's only ever one
      # underlying Tcl trace per Var, wired once at realize, so callbacks
      # added later just join the same list.
      # @yield [value] the new, coerced value
      # @return [self]
      def on_change(&block)
        @on_change_callbacks << block
        self
      end

      # Create the backing Tcl variable, set its initial value, and wire the
      # change trace. Called once by {Session#realize}, before the widget
      # tree realizes, so bound widgets display the initial value from the
      # moment they're created rather than starting blank.
      # @api private
      def realize(app)
        @app = app
        @app.set_variable(@name, to_tcl(@initial))
        cb_id = @app.register_callback(proc { |*| notify_change })
        @app.tcl_eval("trace add variable #{@name} write {ruby_callback #{cb_id}}")
      end

      private

      def notify_change
        current = coerce(@app.get_variable(@name))
        @on_change_callbacks.each { |callback| callback.call(current) }
      end

      def to_tcl(v)
        case v
        when true then '1'
        when false then '0'
        else v.to_s
        end
      end

      def coerce(raw)
        case @initial
        when Integer then raw.to_i
        when Float then raw.to_f
        when true, false then raw == '1'
        else raw
        end
      end

      def raise_unless_realized!
        raise NotRealizedError unless @app
      end
    end
  end
end
