# frozen_string_literal: true

module Teek
  # @api private
  #
  # Registry of per-Tk-widget-type interceptors that App#command consults
  # before falling back to its own generic handling. Each interceptor is a
  # labeled block registered under a widget type string (the same strings
  # used in WIDGET_COMMANDS); App#command looks up the type for the path it
  # was given (see App#record_widget_type) and tries every interceptor
  # registered for that type.
  #
  # An interceptor block receives (app, path, args, kwargs) and must
  # return nil if this call isn't its concern - Tcl results from
  # App#raw_command are always Strings, never nil, so nil is an
  # unambiguous "not mine" sentinel - or the Tcl result if it handled the
  # call itself (typically by calling App#raw_command internally).
  #
  # Multiple widget types can share the same interceptor logic (text and
  # ttk::treeview tag bindings are byte-identical in Tcl shape) by
  # registering the same block under each type. The +label+ is what
  # App#command reports if two DIFFERENT interceptors both claim the same
  # call for the same type - it raises AmbiguousCommandError naming both
  # labels rather than silently picking one, so whoever's debugging can
  # tell which interceptors collided (built-in shape-matching bug, a
  # custom interceptor overlapping a built-in one, two custom interceptors
  # overlapping each other, ...).
  class CommandInterceptors
    Entry = Struct.new(:label, :block)

    class << self
      def register(type, label, &block)
        interceptors[type.to_s] << Entry.new(label.to_s, block)
      end

      def for_type(type)
        interceptors[type.to_s]
      end

      private

      def interceptors
        @interceptors ||= Hash.new { |h, k| h[k] = [] }
      end
    end
  end
end
