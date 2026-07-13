# frozen_string_literal: true

require_relative 'handle'
require_relative 'var'
require_relative 'menu_builder'

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
      #
      # `column`/`row` additionally get flow-layout packing from the
      # realizer (see {Realizer::FLOW}) driven by their own `gap:`/`align:`/
      # `pad:` options; `grid` gets real Tk grid arrangement driven by
      # `#cell`/`#stretch` (below); the others keep the plain unconditional
      # pack every container has always gotten.
      CONTAINER_TYPES = %i[panel group canvas window column row grid].freeze

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

      # A flexible gap - the named replacement for the "invisible spring
      # row" trick (an empty row/column given all the leftover weight).
      # Just a leaf with `grow: true` baked in; nothing to configure.
      # @return [Handle]
      def spacer
        append_leaf(:spacer, nil, grow: true)
      end

      # Look up a named widget declared anywhere in this build.
      # @param name [Symbol]
      # @return [Handle, nil]
      def [](name)
        node = @document.find(name)
        node && Handle.new(node)
      end

      # Position the single widget declared in the block at (row, col) in
      # the enclosing `ui.grid`. Only valid directly inside a grid's block.
      # @param row [Integer]
      # @param col [Integer]
      # @param span [Integer] how many columns this cell spans
      # @return [void]
      def cell(row:, col:, span: 1)
        grid_node = current_grid!('cell')

        before = grid_node.children.length
        yield self if block_given?
        placed = grid_node.children[before..]

        unless placed.length == 1
          raise ArgumentError, "cell needs exactly one widget declared in its block (got #{placed.length})"
        end

        node = placed.first
        node.layout = (node.layout || {}).merge(cell: { row: row, col: col, span: span })
      end

      # Mark which columns/rows of the enclosing `ui.grid` absorb leftover
      # space - the named replacement for `grid columnconfigure -weight`.
      # Only valid directly inside a grid's block.
      # @param columns [Array<Integer>]
      # @param rows [Array<Integer>]
      # @return [void]
      def stretch(columns: [], rows: [])
        grid_node = current_grid!('stretch')

        grid_node.opts[:stretch_columns] = Array(columns) if columns.any?
        grid_node.opts[:stretch_rows] = Array(rows) if rows.any?
      end

      # Node types a menu_bar is allowed to attach to - the root window
      # itself, or a ui.window toplevel. Attaching a -menu to anything else
      # (a plain frame) isn't a real Tk option, so this fails fast at
      # declaration time rather than surfacing as a cryptic Tcl error later.
      MENU_BAR_HOSTS = %i[root window].freeze

      # A window's menu bar - the row of top-level dropdowns (File/Edit/...)
      # along its top edge. Valid at the top level of a build or directly
      # inside `ui.window` - attaches to whichever of those it's declared
      # in once realized.
      # @param name [Symbol, nil]
      # @yieldparam mb [MenuBuilder]
      # @return [Handle]
      # @raise [ArgumentError] if declared anywhere other than the top level or directly inside ui.window
      def menu_bar(name = nil, **opts, &block)
        parent = @stack.last
        unless MENU_BAR_HOSTS.include?(parent.type)
          raise ArgumentError, "menu_bar can only be declared at the top level of a build or directly inside ui.window"
        end

        node = @document.create(type: :menu_bar, name: name, opts: opts)
        parent.add_child(node)
        build_menu_subtree(node, &block)
        Handle.new(node)
      end

      # A standalone popup menu - built the same declarative way as a
      # menu_bar's dropdowns, but not attached to anything automatically.
      # Wire it to a widget with `handle.on_right_click(this)`.
      # @param name [Symbol, nil]
      # @yieldparam m [MenuBuilder]
      # @return [Handle]
      def context_menu(name = nil, **opts, &block)
        node = @document.create(type: :context_menu, name: name, opts: opts)
        @stack.last.add_child(node)
        build_menu_subtree(node, &block)
        Handle.new(node)
      end

      # The build-time escape hatch. A widget has no Tk path yet during
      # build, so `app.command(handle.path, ...)` mid-build can't work -
      # `ui.raw` defers the block instead, running it at realize with the
      # live app in scope. It's a closure, so it can still reference sibling
      # widgets by name (`ui[:other].path`) even if they're declared later -
      # by the time any raw block runs, the whole tree has already been
      # realized once over (same forward-reference guarantee event target:
      # gets). For anything after realize, a live {Handle}/`session.app` is
      # the escape hatch instead - see the README for the full split.
      # @yieldparam app [Teek::App]
      # @return [nil]
      def raw(&block)
        node = @document.create(type: :raw_op, opts: { block: block })
        @stack.last.add_child(node)
        nil
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

      def build_menu_subtree(node, &block)
        return unless block

        @stack.push(node)
        begin
          block.call(MenuBuilder.new(@document, @stack))
        ensure
          @stack.pop
        end
      end

      def append_leaf(type, name, opts)
        opts, layout = extract_layout(resolve_bind(type, opts))
        node = @document.create(type: type, name: name, opts: opts)
        node.layout = layout if layout
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

      # `grow:` is this child's intent within its parent, not a Tk option -
      # pull it off opts (so it never reaches a widget-creation call) and
      # onto the node's own layout slot, where the realizer's flow packing
      # looks for it.
      def extract_layout(opts)
        return [opts, nil] unless opts.key?(:grow)

        [opts.reject { |k, _| k == :grow }, { grow: opts[:grow] }]
      end

      def current_grid!(method_name)
        grid_node = @stack.last
        unless grid_node.type == :grid
          raise ArgumentError, "##{method_name} can only be used directly inside ui.grid"
        end

        grid_node
      end

      def append_container(type, name, opts)
        opts, layout = extract_layout(opts)
        node = @document.create(type: type, name: name, opts: opts)
        node.layout = layout if layout
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
