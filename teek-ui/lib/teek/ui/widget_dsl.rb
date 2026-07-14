# frozen_string_literal: true

require_relative 'errors'
require_relative 'handle'
require_relative 'var'
require_relative 'menu_builder'
require_relative 'screens'
require_relative 'modal_stack'
require_relative 'widget_types'

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
    # all three up in +initialize+. They must also provide +#build_open?+
    # (a predicate the tree-mutating methods below check via
    # {#raise_if_closed!} - true before the initial realize and again for
    # the duration of an +#add+ block, false otherwise).
    module WidgetDSL
      # Every widget/container type - leaf or container, plain or special -
      # gets its own `ui.<type>` method(s) here, generated from its own
      # {WidgetType} descriptor (see {WidgetTypes}) rather than a
      # hardcoded per-type list. {WidgetTypes.on_register} replays every
      # type already registered (every built-in loads before this file
      # does) and keeps firing for any registered later, so a type
      # registered by third-party code lights up here with no edit to
      # this file at all. A type reachable only via a bespoke,
      # hand-written method below (`#tab`/`#pane`/`#split`, `#menu_bar`/
      # `#context_menu`) sets its own descriptor's `dsl:` to a no-op, so
      # this never shadows those with a same-named generic method.
      WidgetTypes.on_register { |widget_type| widget_type.define_dsl_method!(self) }

      # `box` is a bare alternate spelling of `panel` - same node type, so
      # the realizer only ever has to know about `:panel`.
      def box(name = nil, **opts, &block)
        append_container(:panel, name, opts, &block)
      end

      # `window` with dialog-appropriate defaults - modal and fixed-size,
      # for the common "small modal window" case (confirmations, pickers).
      # Same underlying node type as `window`, just different defaults for
      # `modal:`/`resizable:` - both still overridable.
      # @return [Handle]
      def dialog(name = nil, modal: true, resizable: false, **opts, &block)
        append_container(:window, name, opts.merge(modal: modal, resizable: resizable), &block)
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

      # One page of an enclosing `ui.tabs`, labeled `label` in the tab bar.
      # Only valid directly inside a `ui.tabs` block; its own block builds
      # the pane's content with the ordinary widget DSL, same as any other
      # container.
      # @param label [String] the tab's title, shown in the tab bar
      # @param name [Symbol, nil] for `ui[:name]` lookup, same as any widget
      # @return [Handle]
      # @raise [ArgumentError] if declared anywhere other than directly inside ui.tabs
      def tab(label, name = nil, **opts, &block)
        current_tabs!('tab')
        append_container(:tab, name, opts.merge(tab_label: label), &block)
      end

      # Orientation values a `ui.split` accepts - the same plain words Tk's
      # own -orient option uses, so no translation is needed at realize.
      ORIENTATIONS = %i[horizontal vertical].freeze

      # A draggable split - two or more `#pane`-declared regions, resizable
      # by dragging the sash between them. Maps to `ttk::panedwindow`.
      # @param name [Symbol, nil] for `ui[:name]` lookup, same as any widget
      # @param orientation [Symbol] +:horizontal+ (panes side by side, a
      #   vertical sash) or +:vertical+ (panes stacked, a horizontal sash)
      # @yieldparam s [self] build panes with `s.pane { ... }`
      # @return [Handle]
      # @raise [ArgumentError] if orientation isn't :horizontal or :vertical
      def split(name = nil, orientation: :horizontal, **opts, &block)
        unless ORIENTATIONS.include?(orientation)
          raise ArgumentError, "split's orientation must be :horizontal or :vertical (got #{orientation.inspect})"
        end

        append_container(:split, name, opts.merge(orient: orientation.to_s), &block)
      end

      # One region of an enclosing `ui.split`. Only valid directly inside a
      # `ui.split` block; its own block builds the pane's content with the
      # ordinary widget DSL, same as any other container.
      # @param name [Symbol, nil] for `ui[:name]` lookup, same as any widget
      # @param weight [Integer, nil] how much of the leftover space this
      #   pane absorbs when the split is resized, relative to its sibling
      #   panes' weights - unset panes get Tk's own default (0, fixed size
      #   until dragged). The same plain word `ttk::panedwindow` itself
      #   uses for this.
      # @return [Handle]
      # @raise [ArgumentError] if declared anywhere other than directly inside ui.split
      def pane(name = nil, weight: nil, **opts, &block)
        current_split!('pane')
        opts = weight.nil? ? opts : opts.merge(pane_weight: weight)
        append_container(:pane, name, opts, &block)
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
        raise_if_closed!
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
        raise_if_closed!
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
        raise_if_closed!
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
        raise_if_closed!
        @var_count = (@var_count || 0) + 1
        v = Var.new("::teek_ui_var_#{@var_count}", initial)
        @vars << v
        v
      end

      # A push/pop stack for content screens - see {Screens}. One stack per
      # build, created on first access.
      # @return [Screens]
      def screens
        @screens ||= Screens.new
      end

      # A push/pop stack for modal window handles - see {ModalStack}. `nil`
      # until assigned; unlike {#screens} it isn't created automatically,
      # since its callbacks (`on_enter:`/`on_exit:`) are mandatory and
      # app-specific: `ui.modal = Teek::UI::ModalStack.new(on_enter:, on_exit:)`.
      # @return [ModalStack, nil]
      attr_accessor :modal

      private

      # The tree is only ever walked into Tk once (at realize) - a node
      # appended afterward, outside an {Session#add} block, would just sit
      # in the tree forever and never show up, with no error to say why.
      # Every tree-mutating build method checks this first instead.
      def raise_if_closed!
        raise ClosedBuilderError unless build_open?
      end

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
        raise_if_closed!
        validate_scroll!(type, opts)
        opts, layout = extract_layout(resolve_bind(type, opts))
        node = @document.create(type: type, name: name, opts: opts)
        node.layout = layout if layout
        @stack.last.add_child(node)
        Handle.new(node)
      end

      def resolve_bind(type, opts)
        return opts unless opts.key?(:bind)

        tk_option = bind_option_for(type) or
          raise ArgumentError, "##{type} doesn't support bind: (no bindable Tk option is mapped for it)"
        opts.reject { |k, _| k == :bind }.merge(tk_option => opts[:bind].name)
      end

      # Every leaf/container that supports `bind:` is {WidgetType}-registered
      # now, so this is just its descriptor's own `bind_option:` - `nil`
      # (raising below) for anything unregistered or genuinely unsupported.
      def bind_option_for(type)
        WidgetTypes.for_type(type)&.bind_option
      end

      def validate_scroll!(type, opts)
        return unless opts.key?(:scroll)
        return if natively_scrollable_for?(type)

        raise ArgumentError, "##{type} doesn't support scroll: (only #{scrollable_type_names.join('/')} do)"
      end

      # Every type that has ever supported `scroll:` is {WidgetType}-registered
      # now (list/text_area/table/tree/canvas), so this is just its
      # descriptor's own `natively_scrollable?` - `false` for anything
      # unregistered.
      def natively_scrollable_for?(type)
        WidgetTypes.for_type(type)&.natively_scrollable? || false
      end

      # The full set of types `scroll:` actually works on, for the error
      # message above.
      def scrollable_type_names
        WidgetTypes.each.select(&:natively_scrollable?).map(&:type).sort
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

      def current_tabs!(method_name)
        tabs_node = @stack.last
        unless tabs_node.type == :tabs
          raise ArgumentError, "##{method_name} can only be used directly inside ui.tabs"
        end

        tabs_node
      end

      def current_split!(method_name)
        split_node = @stack.last
        unless split_node.type == :split
          raise ArgumentError, "##{method_name} can only be used directly inside ui.split"
        end

        split_node
      end

      def append_container(type, name, opts)
        raise_if_closed!
        validate_scroll!(type, opts)
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
