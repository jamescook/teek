# frozen_string_literal: true

require_relative 'handle'

module Teek
  module UI
    # The build surface: `ui.<widget>` methods that APPEND nodes to the
    # {Document} tree. They never touch Tk - widgets become live only when
    # the realizer runs at realize.
    #
    # Names are deliberately Tk-free (the litmus test: if decoding a name
    # needs Tk knowledge, the name is wrong) - see the design sketch for the
    # full vocabulary rationale.
    #
    # Mixed into {Session} rather than living on a separate accessor, so the
    # DSL reads as `ui.button(...)`, not `ui.widgets.button(...)`.
    #
    # Included classes must provide +@document+ (a {Document}) and
    # +@stack+ (an Array of {Node}, current-parent stack seeded with
    # +@document.root+) - {Session} sets both up in +initialize+.
    module WidgetDSL
      # Widget kinds with no children of their own - just options.
      LEAF_TYPES = %i[
        text_box text_area label button checkbox radio slider dropdown
        number_box list table tree progress divider
      ].freeze

      # Widget kinds that hold children, declared in a block. The block
      # yields the same builder object back (not a separate scoped builder),
      # so a name declared inside it is addressable from outside too.
      CONTAINER_TYPES = %i[panel group canvas window].freeze

      LEAF_TYPES.each do |leaf_type|
        define_method(leaf_type) do |name = nil, **opts|
          append_leaf(leaf_type, name, opts)
        end
      end

      CONTAINER_TYPES.each do |container_type|
        define_method(container_type) do |name = nil, **opts, &block|
          append_container(container_type, name, opts, &block)
        end
      end

      # `box` is a bare alternate spelling of `panel` - same node type, so
      # the realizer only ever has to know about `:panel`.
      def box(name = nil, **opts, &block)
        append_container(:panel, name, opts, &block)
      end

      # Look up a named widget declared anywhere in this build.
      # @param name [Symbol]
      # @return [Handle, nil]
      def [](name)
        node = @document.find(name)
        node && Handle.new(node)
      end

      private

      def append_leaf(type, name, opts)
        node = @document.create(type: type, name: name, opts: opts)
        @stack.last.add_child(node)
        Handle.new(node)
      end

      def append_container(type, name, opts)
        node = @document.create(type: type, name: name, opts: opts)
        @stack.last.add_child(node)

        if block_given?
          @stack.push(node)
          begin
            yield self
          ensure
            @stack.pop
          end
        end

        Handle.new(node)
      end
    end
  end
end
