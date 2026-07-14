# frozen_string_literal: true

require_relative 'realized_node'

module Teek
  module UI
    # Walks a {Document} and realizes it into a live {Teek::App} - two
    # passes (Resolved decision #4 in the architecture doc):
    #
    # 1. +create+ - creates every widget, allocates a hierarchical/meaningful
    #    Tk path per node, fills each node's +realized+ slot.
    # 2. +link+ - applies (placeholder, see below) geometry and wires event
    #    bindings, resolving +target:+ references by name. Runs after
    #    +create+ has finished the WHOLE tree, so a target declared later in
    #    the build already has a live path by the time it's looked up - that
    #    ordering is what makes forward references work.
    #
    # Every widget creation and mutation goes through {Teek::App#command}, so
    # teek's interceptor/leak-cleanup layer applies automatically.
    #
    # @note Layout is real for +:column+/+:row+ (flow packing driven by
    #   +gap:+/+align:+/+pad:+ and each child's +grow:+) and +:grid+ (real Tk
    #   grid arrangement driven by +#cell+/+#stretch+), but still a
    #   placeholder for every other container type - their children just
    #   pack top-to-bottom with no options. There's no overlay layout yet.
    class Realizer
      # DSL node type -> Tk widget-creation command.
      TK_COMMANDS = {
        text_box: 'ttk::entry',
        text_area: 'text',
        label: 'ttk::label',
        button: 'ttk::button',
        checkbox: 'ttk::checkbutton',
        radio: 'ttk::radiobutton',
        slider: 'ttk::scale',
        dropdown: 'ttk::combobox',
        number_box: 'ttk::spinbox',
        list: 'listbox',
        table: 'ttk::treeview',
        tree: 'ttk::treeview',
        progress: 'ttk::progressbar',
        divider: 'ttk::separator',
        panel: 'ttk::frame',
        group: 'ttk::labelframe',
        canvas: 'canvas',
        window: 'toplevel',
        column: 'ttk::frame',
        row: 'ttk::frame',
        spacer: 'ttk::frame',
        grid: 'ttk::frame',
        scrollable: 'ttk::frame',
      }.freeze

      # DSL-reserved opts keys - layout keywords (gap:/align:/pad:/
      # stretch_columns/stretch_rows) plus other entries the DSL stashes on
      # node.opts for the realizer to pick up later (on_close:, and title:/
      # geometry:/resizable:/transient:/modal: for :window nodes, applied by
      # #setup_window; x:/y: for :scrollable nodes, applied by
      # #create_scrollable) - none of these are real Tk options, so none
      # are ever passed through to a widget-creation call.
      RESERVED_OPTIONS = %i[
        gap align pad stretch_columns stretch_rows on_close
        title geometry resizable transient modal x y
      ].freeze

      # Widget types that already speak Tk's native scrolling protocol
      # (-yscrollcommand/-xscrollcommand + yview/xview) - a :scrollable
      # whose single child is one of these wires a scrollbar straight to
      # it. Anything else (no children, several, or a plain container) is
      # wrapped in a canvas + embedded frame instead - the classic Tk
      # "scrollable frame" trick, since arbitrary widgets have no
      # scrolling protocol of their own to hook a scrollbar into.
      NATIVELY_SCROLLABLE_TYPES = %i[list text_area table tree canvas].freeze

      # :column/:row flow-packing config, mirrored across the main axis
      # (stack direction) and cross axis (perpendicular to it).
      FLOW = {
        column: {
          side: 'top', main_pad: :pady, cross_pad: :padx,
          main_fill: 'y', cross_fill: 'x',
          anchor: { start: 'w', center: 'center', end: 'e' },
        },
        row: {
          side: 'left', main_pad: :padx, cross_pad: :pady,
          main_fill: 'x', cross_fill: 'y',
          anchor: { start: 'n', center: 'center', end: 's' },
        },
      }.freeze

      # @api private
      def initialize(app, document)
        @app = app
        @document = document
      end

      # @return [void]
      def realize
        create(@document.root, '.')
        link(@document.root)
      end

      # Realize a single already-built (but not-yet-realized) node - and its
      # descendants - into an already-running app, scoped under a parent
      # that's realized already. Reuses the exact same create/link machinery
      # {#realize} uses for the initial tree, just entered at an arbitrary
      # node instead of the document root - see {Session#add}.
      # @param node [Node] freshly built, not yet realized
      # @param parent_node [Node] already realized - node becomes its child
      # @return [void]
      def realize_subtree(node, parent_node)
        create(node, parent_node.realized.path)
        # re-arrange ALL of parent_node's children (old + new), not just the
        # new one in isolation - gap:/align: positioning depends on a
        # child's index relative to every sibling, not just itself.
        arrange_children(parent_node)
        link(node)
      end

      private

      # Node types with no Tk representation of their own - skipped by
      # create's widget-creation step, and (for :raw_op) by every
      # container's arrangement step too, since they have no realized path.
      NON_WIDGET_TYPES = %i[root raw_op].freeze

      # menu_bar/context_menu are the two entry points into a menu subtree -
      # everything under them (nested :menu cascades, :menu_item/
      # :menu_separator/:menu_checkbox/:menu_radio entries) is built in one
      # shot by create_menu_tree, in menu-add order, rather than through the
      # generic per-node create/link passes every other node type uses -
      # menu entries have no Tk path or geometry-managed arrangement of
      # their own to visit separately.
      MENU_ROOT_TYPES = %i[menu_bar context_menu].freeze

      def create(node, parent_path)
        if MENU_ROOT_TYPES.include?(node.type)
          create_menu_tree(node, parent_path)
          return
        end

        path =
          if NON_WIDGET_TYPES.include?(node.type)
            parent_path
          else
            allocate_path(node, parent_path)
          end

        unless NON_WIDGET_TYPES.include?(node.type)
          tk_command = TK_COMMANDS.fetch(node.type) {
            raise ArgumentError, "no Tk command mapped for node type :#{node.type}"
          }
          @app.command(tk_command, path, **node.opts.except(*RESERVED_OPTIONS))
          node.realized = RealizedNode.new(app: @app, path: path)
          setup_window(node, path, parent_path) if node.type == :window
        end

        if node.type == :scrollable
          create_scrollable(node, path)
        else
          node.children.each { |child| create(child, path) }
        end
      end

      # Sets up a freshly created toplevel: title/geometry/resizable setup,
      # transient-to-parent (the parent it's actually nested under in this
      # build, not always the root - computed from parent_path, which is
      # '.' for a top-level ui.window and another window's own path when
      # nested inside one), the macOS shared-menubar quirk (each platform
      # other than macOS gets its own menu bar per window; macOS has a
      # single app-wide menu bar, so without this a new window falls back
      # to Tk's default "wish" menu instead of the parent's), and withdrawn
      # by default - shown explicitly via Handle#show.
      def setup_window(node, path, parent_path)
        opts = node.opts
        window = @app.window(path)

        window.set_title(opts[:title]) if opts[:title]
        window.set_geometry(opts[:geometry]) if opts[:geometry]
        if opts.key?(:resizable)
          pair = opts[:resizable]
          width, height = pair.is_a?(Array) ? pair : [pair, pair]
          window.set_resizable(width, height)
        end
        @app.command(:wm, :transient, path, parent_path) unless opts[:transient] == false
        share_macos_menu(path, parent_path) if Teek.platform.darwin?
        window.withdraw
      end

      def share_macos_menu(path, parent_path)
        parent_menu = @app.command(parent_path, :cget, '-menu')
        @app.command(path, :configure, menu: parent_menu) unless parent_menu.nil? || parent_menu.empty?
      rescue Teek::TclError
        nil
      end

      # A :scrollable's own widget (created just before this runs) is a
      # plain ttk::frame at +path+ - this fills it in, taking over child
      # creation instead of the generic node.children.each loop #create
      # otherwise uses, since where a :scrollable's children actually live
      # in the Tk tree depends on which of the two cases below applies.
      #
      # Native case (single child, a listbox/text/treeview/canvas): the
      # child is created directly under +path+ as usual, then a scrollbar
      # is wired straight to it (-yscrollcommand/-xscrollcommand + its own
      # -command calling back to +yview+/+xview+) - zero extra widgets.
      #
      # Frame case (anything else - no children, several, or a plain
      # container): there's no Tk protocol to hook a scrollbar into
      # arbitrary widgets, so children are created inside an embedded
      # frame instead - +path+.canvas.viewport - packed inside a canvas
      # that the scrollbar drives. The viewport's own size changes (as its
      # content changes) keep the canvas's -scrollregion in sync; unless
      # horizontal scrolling is on, the canvas's own size changes keep the
      # viewport's width matched to it too, so content isn't left
      # narrower than the visible area.
      def create_scrollable(node, path)
        y = node.opts.fetch(:y, true)
        x = node.opts.fetch(:x, false)
        child = native_scrollable_child(node)

        if child
          create(child, path)
          wire_scrollbars(path, child.realized.path, x: x, y: y)
        else
          canvas_path = "#{path}.canvas"
          viewport_path = "#{canvas_path}.viewport"
          @app.command('canvas', canvas_path, highlightthickness: 0)
          @app.command('ttk::frame', viewport_path)
          window_id = @app.command(canvas_path, :create, :window, 0, 0, window: viewport_path, anchor: 'nw')

          node.children.each { |grandchild| create(grandchild, viewport_path) }

          @app.bind(viewport_path, '<Configure>') {
            @app.command(canvas_path, :configure, scrollregion: @app.command(canvas_path, :bbox, :all))
          }
          unless x
            @app.bind(canvas_path, '<Configure>', :width) { |width|
              @app.command(canvas_path, :itemconfigure, window_id, width: width)
            }
          end

          wire_scrollbars(path, canvas_path, x: x, y: y)
          wire_wheel_scroll(canvas_path, viewport_path, node, x: x, y: y)
        end
      end

      def wire_scrollbars(path, target_path, x:, y:)
        vsb_path = "#{path}.vsb"
        hsb_path = "#{path}.hsb"

        if y
          @app.command('ttk::scrollbar', vsb_path, orient: 'vertical', command: "#{target_path} yview")
          @app.command(target_path, :configure, yscrollcommand: "#{vsb_path} set")
        end
        if x
          @app.command('ttk::scrollbar', hsb_path, orient: 'horizontal', command: "#{target_path} xview")
          @app.command(target_path, :configure, xscrollcommand: "#{hsb_path} set")
        end

        @app.command(:grid, target_path, row: 0, column: 0, sticky: 'nsew')
        @app.command(:grid, vsb_path, row: 0, column: 1, sticky: 'ns') if y
        @app.command(:grid, hsb_path, row: 1, column: 0, sticky: 'ew') if x
        @app.command(:grid, :columnconfigure, path, 0, weight: 1)
        @app.command(:grid, :rowconfigure, path, 0, weight: 1)
      end

      # Tk's own Scrollbar class binds <MouseWheel> at this same ratio (see
      # scrlbar.tcl) - matched here so wheeling directly over the frame
      # case's content feels identical to wheeling over its scrollbar.
      WHEEL_UNITS_PER_NOTCH = 40.0

      # The frame case's scrollbar and -yscrollcommand/-xscrollcommand
      # wiring (see #wire_scrollbars) only covers dragging the scrollbar
      # itself - the canvas has no default wheel handling of its own (a
      # bare canvas isn't a Scrollbar), and neither do any of the
      # arbitrary widgets embedded in its viewport. A <MouseWheel>/
      # <Button-4>/<Button-5> binding placed directly on the canvas alone
      # wouldn't fire for those descendants either: Tk delivers pointer
      # events to whichever widget is actually under the cursor, and a
      # child widget layered inside the viewport intercepts them before
      # the canvas ever sees them.
      #
      # The fix is the classic one - give the canvas, the viewport, and
      # every widget already inside it (walked recursively, since new
      # widgets can nest arbitrarily deep) a shared custom bindtag, and
      # bind the wheel handler once on that tag instead of on any single
      # widget. Every widget carrying the tag then responds identically,
      # regardless of which one the pointer happens to be over - the same
      # mechanism Tk's own class bindings (Button, Entry, ...) use, just
      # scoped to this one scrollable region instead of a widget class.
      #
      # @note widgets added later via +Session#add+ don't pick up the tag
      #   automatically - wheel-scrolling a scrollable frame's dynamically
      #   added content isn't covered yet.
      def wire_wheel_scroll(canvas_path, viewport_path, node, x:, y:)
        return unless x || y

        tag = "TeekScrollRegion#{canvas_path.tr('.', '_')}"
        add_bindtag(canvas_path, tag)
        add_bindtag(viewport_path, tag)
        node.children.each { |child| child.each { |descendant| add_bindtag(descendant.realized.path, tag) if descendant.realized } }

        if y
          @app.bind(tag, '<MouseWheel>', :mouse_wheel) { |delta|
            @app.command(canvas_path, :yview, :scroll, delta.to_f / -WHEEL_UNITS_PER_NOTCH, :units)
          }
          @app.bind(tag, '<Button-4>') { @app.command(canvas_path, :yview, :scroll, -1, :units) }
          @app.bind(tag, '<Button-5>') { @app.command(canvas_path, :yview, :scroll, 1, :units) }
        end
        if x
          @app.bind(tag, '<Shift-MouseWheel>', :mouse_wheel) { |delta|
            @app.command(canvas_path, :xview, :scroll, delta.to_f / -WHEEL_UNITS_PER_NOTCH, :units)
          }
          @app.bind(tag, '<Shift-Button-4>') { @app.command(canvas_path, :xview, :scroll, -1, :units) }
          @app.bind(tag, '<Shift-Button-5>') { @app.command(canvas_path, :xview, :scroll, 1, :units) }
        end
      end

      def add_bindtag(path, tag)
        current = @app.split_list(@app.command(:bindtags, path))
        @app.command(:bindtags, path, current + [tag])
      end

      def native_scrollable_child(node)
        return nil unless node.children.length == 1

        candidate = node.children.first
        NATIVELY_SCROLLABLE_TYPES.include?(candidate.type) ? candidate : nil
      end

      # Builds one menu widget (a menu_bar, a nested cascade, or a
      # standalone context_menu) plus every entry it holds, recursing into
      # nested cascades depth-first so a cascade's own menu exists before
      # the `add cascade` entry that references it is added to its parent.
      # A menu_bar additionally attaches itself to parent_path's own -menu
      # option once its whole subtree is built.
      def create_menu_tree(node, parent_path)
        path = allocate_path(node, parent_path)
        @app.menu(path)
        node.realized = RealizedNode.new(app: @app, path: path)

        node.children.each do |child|
          case child.type
          when :menu
            create_menu_tree(child, path)
            @app.command(path, :add, :cascade, **child.opts, menu: child.realized.path)
          when :menu_item
            @app.command(path, :add, :command, **menu_entry_opts(child))
          when :menu_separator
            @app.command(path, :add, :separator)
          when :menu_checkbox
            @app.command(path, :add, :checkbutton, **menu_entry_opts(child))
          when :menu_radio
            @app.command(path, :add, :radiobutton, **menu_entry_opts(child))
          else
            raise ArgumentError, "#{describe(child)} isn't valid inside a menu"
          end
        end

        @app.command(parent_path, :configure, menu: path) if node.type == :menu_bar
      end

      def menu_entry_opts(node)
        bind = node.opts[:bind]
        bind ? node.opts.except(:bind).merge(variable: bind.name) : node.opts
      end

      def link(node)
        return if MENU_ROOT_TYPES.include?(node.type)

        arrange_children(node)
        node.events.each { |binding| wire_event(node, binding) }
        run_raw_op(node) if node.type == :raw_op
        wire_close_handler(node) if node.opts[:on_close]
        node.children.each { |child| link(child) }
      end

      def run_raw_op(node)
        node.opts[:block].call(@app)
      end

      def wire_close_handler(node)
        @app.on_close(window: node.realized.path, &node.opts[:on_close])
      end

      # Children a geometry manager should never touch: :raw_op has no
      # realized path at all; :window (a toplevel) is placed by the window
      # manager, not by whatever pack/grid strategy its nominal parent uses
      # (packing/gridding a toplevel into its parent is a Tk error, "it's a
      # top-level window"); :menu_bar/:context_menu attach via their own
      # -menu config / on_right_click wiring, never via pack/grid either.
      NOT_ARRANGED_TYPES = %i[raw_op window menu_bar context_menu].freeze

      def arrange_children(node)
        # The native case already placed its one child with grid (see
        # #wire_scrollbars) - packing it again here would conflict.
        return if node.type == :scrollable && native_scrollable_child(node)

        arrangeable = node.children.reject { |child| NOT_ARRANGED_TYPES.include?(child.type) }

        if FLOW.key?(node.type)
          arrange_flow(node, arrangeable)
        elsif node.type == :grid
          arrange_grid(node, arrangeable)
        elsif node.type == :scrollable
          # The frame case's children live in the embedded viewport frame
          # (see #create_scrollable) - fill/expand by default so content
          # stretches to the visible width instead of hugging its own
          # natural size.
          arrangeable.each { |child| @app.command(:pack, child.realized.path, fill: 'both', expand: true) }
        else
          arrangeable.each { |child| @app.command(:pack, child.realized.path) }
        end
      end

      def arrange_flow(node, children)
        flow = FLOW[node.type]
        gap = node.opts.fetch(:gap, 0)
        align = node.opts.fetch(:align, :start)
        pad = node.opts.fetch(:pad, 0)
        last_index = children.length - 1

        children.each_with_index do |child, index|
          opts = flow_pack_opts(
            flow: flow, child: child, index: index, last_index: last_index,
            gap: gap, align: align, pad: pad
          )
          @app.command(:pack, child.realized.path, **opts)
        end
      end

      def arrange_grid(node, children)
        gap = node.opts.fetch(:gap, 0)

        children.each do |child|
          cell = child.layout && child.layout[:cell]
          unless cell
            raise ArgumentError, "#{describe(child)} is a direct child of a grid but was never placed with " \
                                  "g.cell(row:, col:) { ... }"
          end

          opts = { row: cell[:row], column: cell[:col], sticky: 'ew', padx: gap, pady: gap }
          opts[:columnspan] = cell[:span] if cell[:span].to_i > 1
          @app.command(:grid, child.realized.path, **opts)
        end

        Array(node.opts[:stretch_columns]).each { |col| @app.command(:grid, :columnconfigure, node.realized.path, col, weight: 1) }
        Array(node.opts[:stretch_rows]).each { |row| @app.command(:grid, :rowconfigure, node.realized.path, row, weight: 1) }
      end

      def describe(node)
        node.name ? "##{node.type}(:#{node.name})" : "an unnamed ##{node.type}"
      end

      def flow_pack_opts(flow:, child:, index:, last_index:, gap:, align:, pad:)
        opts = { side: flow[:side] }
        opts[flow[:main_pad]] = [index.zero? ? pad : gap, index == last_index ? pad : 0]
        opts[flow[:cross_pad]] = pad

        grow = child.layout && child.layout[:grow]
        stretch = align == :stretch
        fills = [(flow[:main_fill] if grow), (flow[:cross_fill] if stretch)].compact
        opts[:fill] = fills.length == 2 ? 'both' : fills.first unless fills.empty?
        opts[:expand] = true if grow
        unless stretch
          opts[:anchor] = flow[:anchor].fetch(align) {
            raise ArgumentError, "invalid align: #{align.inspect} (expected :start, :center, :end, or :stretch)"
          }
        end

        opts
      end

      def wire_event(node, binding)
        target_node =
          if binding.target
            @document.find(binding.target) or
              raise ArgumentError, "event target :#{binding.target} not found in the document"
          else
            node
          end

        @app.bind(target_node.realized.path, binding.event, *binding.subs) { |*args| binding.handler.call(*args) }
      end

      def allocate_path(node, parent_path)
        # node.key is unique for the whole Document, persisted at node
        # creation (Document#create) - not a per-Realizer-instance counter,
        # which would collide across separate realize_subtree calls (each
        # gets its own Realizer instance, e.g. one per Session#add call).
        segment = node.name ? node.name.to_s : node.key
        parent_path == '.' ? ".#{segment}" : "#{parent_path}.#{segment}"
      end
    end
  end
end
