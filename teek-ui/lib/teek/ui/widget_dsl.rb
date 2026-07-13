# frozen_string_literal: true

require_relative 'handle'
require_relative 'var'

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
    # Included classes must provide +@document+ (a {Document}), +@stack+
    # (an Array of {Node}, current-parent stack seeded with
    # +@document.root+), and +@vars+ (an Array of {Var}) - {Session} sets
    # all three up in +initialize+.
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

      # Widget type -> the Tk option a bound {Var} plugs into. Not every
      # widget can be bound this way (text_area/list/table/tree/divider have
      # no plain scalar variable option in Tk; radio needs a shared variable
      # plus a per-widget -value, which isn't wired up yet) - `bind:` raises
      # for anything not listed here rather than silently doing nothing.
      BIND_OPTIONS = {
        text_box: :textvariable, label: :textvariable, dropdown: :textvariable, number_box: :textvariable,
        checkbox: :variable, slider: :variable, progress: :variable,
      }.freeze

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

      # Declare a reactive variable. Its Tcl variable name is allocated now
      # (no interpreter needed - it's just a string); the variable itself
      # only becomes real at realize. Bind it to widgets with `bind:`.
      # @param initial [Object] initial value - its class decides how
      #   {Var#value} coerces later (Integer/Float/Boolean typed, else String)
      # @return [Var]
      def var(initial)
        @var_count = (@var_count || 0) + 1
        v = Var.new("::teek_ui_var_#{@var_count}", initial)
        @vars << v
        v
      end

      private

      def append_leaf(type, name, opts)
        opts = resolve_bind(type, opts)
        node = @document.create(type: type, name: name, opts: opts)
        @stack.last.add_child(node)
        Handle.new(node)
      end

      def resolve_bind(type, opts)
        return opts unless opts.key?(:bind)

        tk_option = BIND_OPTIONS.fetch(type) {
          raise ArgumentError, "##{type} doesn't support bind: (no bindable Tk option is mapped for it)"
        }
        opts.reject { |k, _| k == :bind }.merge(tk_option => opts[:bind].name)
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
