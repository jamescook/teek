# frozen_string_literal: true

require_relative 'errors'

module Teek
  module UI
    # A DSL-declared image, backed by teek core's {Teek::Photo} (which
    # owns the underlying Tk image's GC lifetime - see its own docs).
    #
    # Declared via {WidgetDSL#image} at build time - its Tcl image name
    # is allocated purely in Ruby, no interpreter needed yet (same shape
    # as {Var}'s own Tcl variable name), so it can be captured as a
    # widget's `image:` option (or a later `handle.configure(image: ...)`
    # value) before realize even happens. The real {Teek::Photo} - and
    # the actual file load - only exists at #realize.
    #
    # #to_s returns the Tcl name (matching {Teek::Photo}'s own
    # convention), so passing an Image directly as an `image:` option
    # value works through teek's ordinary option-value serialization -
    # no special-casing needed anywhere in the widget DSL for it.
    class Image
      # @return [String] the Tcl image name
      attr_reader :name

      # @api private
      def initialize(name, path, opts)
        @name = name
        @path = path
        @opts = opts
        @photo = nil
      end

      # @return [Teek::Photo] the live, GC-owned Tk photo image, loaded
      #   from the file path this was declared with
      # @raise [NotRealizedError] before realize
      def photo
        @photo or raise NotRealizedError
      end

      # Loads the backing {Teek::Photo} from this image's file path.
      # Called once by {Session#realize}, before the widget tree
      # realizes, so any widget's `image:` option already resolves to a
      # real, loaded image by the time it's created.
      # @api private
      def realize(app)
        @photo = Teek::Photo.new(app, name: @name, file: @path, **@opts)
      end

      # @return [String] the Tcl image name - lets this be passed
      #   directly as a widget's `image:` option, at build time or via a
      #   later `handle.configure(image: ...)`, the same way
      #   {Teek::Photo} itself already can be.
      def to_s
        @name
      end
    end
  end
end
