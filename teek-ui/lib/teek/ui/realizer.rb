# frozen_string_literal: true

require_relative 'realized_node'
require_relative 'widget_types'

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
      # DSL node type -> Tk widget-creation command, for any type not yet
      # migrated to a {WidgetType} descriptor (see {WidgetTypes}) - a
      # registered type's tk_command comes from its own descriptor instead
      # (see {#tk_command_for}). `:divider` is the first migrated leaf, so
      # it's no longer listed here.
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
        panel: 'ttk::frame',
        group: 'ttk::labelframe',
        canvas: 'canvas',
        window: 'toplevel',
        column: 'ttk::frame',
        row: 'ttk::frame',
        spacer: 'ttk::frame',
        grid: 'ttk::frame',
        scrollable: 'ttk::frame',
        tabs: 'ttk::notebook',
        tab: 'ttk::frame',
        split: 'ttk::panedwindow',
        pane: 'ttk::frame',
      }.freeze

      # DSL-reserved opts keys - layout keywords (gap:/align:/pad:/
      # stretch_columns/stretch_rows) plus other entries the DSL stashes on
      # node.opts for the realizer to pick up later (on_close:, and title:/
      # geometry:/resizable:/transient:/modal: for :window nodes, applied by
      # #setup_window; x:/y: for :scrollable and native-scrollable nodes,
      # applied by #create_scrollable/#create_native_scrollable; scroll:
      # for native-scrollable nodes, applied by #auto_scrollable?; tab_label
      # for :tab nodes, applied by #setup_tab; pane_weight for :pane nodes,
      # applied by #setup_pane) - none of these are real Tk options, so none
      # are ever passed through to a widget-creation call. +:split+'s own
      # +orient:+ isn't reserved - it's a real `ttk::panedwindow` option
      # already, so it passes straight through.
      RESERVED_OPTIONS = %i[
        gap align pad stretch_columns stretch_rows on_close
        title geometry resizable transient modal x y scroll tab_label pane_weight
      ].freeze

      # Widget types that already speak Tk's native scrolling protocol
      # (-yscrollcommand/-xscrollcommand + yview/xview) - one of these,
      # declared anywhere, auto-attaches a scrollbar wrapper unless
      # #resolve_scroll says otherwise (see #auto_scrollable?). A bare
      # :scrollable (for arbitrary content that has no scrolling protocol
      # of its own) always gets the separate canvas+viewport frame
      # treatment instead - see #create_scrollable.
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
      # @param default_scroll [Boolean, nil] app-wide override for whether
      #   native scrollable widgets auto-attach a scrollbar - see
      #   {Teek::UI.app}'s own +scroll:+. +nil+ defers to the global
      #   default ({Teek::UI.auto_scroll}/{Teek::UI.auto_scroll_canvas}).
      def initialize(app, document, default_scroll: nil)
        @app = app
        @document = document
        @default_scroll = default_scroll
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

      # {WidgetTypes} first, falling back to the legacy {TK_COMMANDS} hash
      # for any type not yet registered as a {WidgetType}.
      def tk_command_for(type)
        registered = WidgetTypes.for_type(type)
        return registered.tk_command if registered

        TK_COMMANDS.fetch(type) { raise ArgumentError, "no Tk command mapped for node type :#{type}" }
      end

      def create(node, parent_path)
        if MENU_ROOT_TYPES.include?(node.type)
          create_menu_tree(node, parent_path)
          return
        end

        if auto_scrollable?(node)
          create_native_scrollable(node, allocate_path(node, parent_path))
          return
        end

        path =
          if NON_WIDGET_TYPES.include?(node.type)
            parent_path
          else
            allocate_path(node, parent_path)
          end

        unless NON_WIDGET_TYPES.include?(node.type)
          @app.command(tk_command_for(node.type), path, **node.opts.except(*RESERVED_OPTIONS))
          node.realized = RealizedNode.new(app: @app, path: path)
          setup_window(node, path, parent_path) if node.type == :window
          setup_tab(node, path, parent_path) if node.type == :tab
          setup_pane(node, path, parent_path) if node.type == :pane
          WidgetTypes.for_type(node.type)&.post_create(@app, node, path)
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

      # Adds a freshly created :tab's own frame (just created at +path+) as
      # a page of the enclosing notebook at +parent_path+, labeled with
      # whatever `#tab` stashed as tab_label:. `ttk::notebook add` is the
      # page's whole placement - unlike every other container, a tab's
      # frame is never pack/grid-managed on its own (see NOT_ARRANGED_TYPES).
      def setup_tab(node, path, parent_path)
        @app.command(parent_path, :add, path, text: node.opts[:tab_label])
      end

      # Adds a freshly created :pane's own frame (just created at +path+) as
      # a pane of the enclosing panedwindow at +parent_path+, with whatever
      # `#pane` stashed as pane_weight: (if any). `ttk::panedwindow add` is
      # the pane's whole placement - unlike every other container, a pane's
      # frame is never pack/grid-managed on its own (see NOT_ARRANGED_TYPES).
      def setup_pane(node, path, parent_path)
        weight = node.opts[:pane_weight]
        opts = weight.nil? ? {} : { weight: weight }
        @app.command(parent_path, :add, path, **opts)
      end

      # Whether +node+ should auto-attach a scrollbar with no explicit
      # +ui.scrollable+ wrapper - only ever true for
      # {NATIVELY_SCROLLABLE_TYPES}, and then only once #resolve_scroll
      # settles the 3-level override (widget's own +scroll:+, then the
      # session's app-wide default, then the global one).
      def auto_scrollable?(node)
        natively_scrollable?(node.type) && resolve_scroll(node)
      end

      # {WidgetTypes} first, falling back to the legacy
      # {NATIVELY_SCROLLABLE_TYPES} list for any type not yet registered as
      # a {WidgetType}.
      def natively_scrollable?(type)
        registered = WidgetTypes.for_type(type)
        return registered.natively_scrollable? if registered

        NATIVELY_SCROLLABLE_TYPES.include?(type)
      end

      def resolve_scroll(node)
        opt = node.opts[:scroll]
        return opt unless opt.nil?
        return @default_scroll unless @default_scroll.nil?

        node.type == :canvas ? Teek::UI.auto_scroll_canvas : Teek::UI.auto_scroll
      end

      # Wraps a bare native-scrollable widget (list/text_area/table/tree/
      # canvas) in the same wrapper-frame-plus-scrollbar structure
      # +ui.scrollable+'s native case used to build explicitly - except
      # nothing in the DSL asked for it, so it has to happen without
      # disturbing what +node+'s own path means to the rest of the app.
      #
      # +path+ (the node's own allocated path, e.g. `.panel.log`) becomes
      # an invisible wrapper frame instead of the widget itself; the real
      # widget lives one level deeper, at +path+.widget. +node.realized+
      # points at the real widget (so a {Handle}'s +#configure+/events/
      # +#path+ keep acting on it directly, unchanged from the
      # non-scrolling case) - only its +arrange_path+ is the wrapper,
      # since that's the widget's actual Tk parent now, and what the
      # surrounding layout needs to pack/grid in the widget's place. See
      # {RealizedNode}.
      def create_native_scrollable(node, path)
        widget_path = "#{path}.widget"
        tk_command = tk_command_for(node.type)

        @app.command('ttk::frame', path)
        @app.command(tk_command, widget_path, **node.opts.except(*RESERVED_OPTIONS))
        node.realized = RealizedNode.new(app: @app, path: widget_path, arrange_path: path)

        wire_scrollbars(path, widget_path, x: node.opts.fetch(:x, false), y: node.opts.fetch(:y, true))
        node.children.each { |child| create(child, widget_path) }
      end

      # A :scrollable's own widget (created just before this runs) is a
      # plain ttk::frame at +path+ - this fills it in, taking over child
      # creation instead of the generic node.children.each loop #create
      # otherwise uses. There's no Tk protocol to hook a scrollbar into
      # arbitrary widgets (unlike the native-scrollable case above, which
      # is why this is the ONLY thing left for +ui.scrollable+ to do -
      # see #auto_scrollable?), so children are created inside an embedded
      # frame instead - +path+.canvas.viewport - packed inside a canvas
      # that the scrollbar drives. The viewport's own size changes (as its
      # content changes) keep the canvas's -scrollregion in sync; unless
      # horizontal scrolling is on, the canvas's own size changes keep the
      # viewport's width matched to it too, so content isn't left
      # narrower than the visible area.
      def create_scrollable(node, path)
        y = node.opts.fetch(:y, true)
        x = node.opts.fetch(:x, false)

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

      # Grids +target_path+ (the scrollable widget/canvas) against a
      # scrollbar per requested axis, inside +path+ (their shared parent).
      # The scrollbar auto-hides once its own -yscrollcommand/
      # -xscrollcommand tells it the content fully fits (Tk hands that
      # callback the visible fraction as +first+/+last+ - 0.0/1.0 means
      # "all of it" - see #auto_hide_scrollbar) - real "overflow: auto",
      # not a bar that's always there whether it's needed or not.
      def wire_scrollbars(path, target_path, x:, y:)
        vsb_path = "#{path}.vsb"
        hsb_path = "#{path}.hsb"

        if y
          @app.command('ttk::scrollbar', vsb_path, orient: 'vertical', command: "#{target_path} yview")
          @app.command(:grid, vsb_path, row: 0, column: 1, sticky: 'ns')
          auto_hide_scrollbar(target_path, vsb_path, option: :yscrollcommand)
        end
        if x
          @app.command('ttk::scrollbar', hsb_path, orient: 'horizontal', command: "#{target_path} xview")
          @app.command(:grid, hsb_path, row: 1, column: 0, sticky: 'ew')
          auto_hide_scrollbar(target_path, hsb_path, option: :xscrollcommand)
        end

        @app.command(:grid, target_path, row: 0, column: 0, sticky: 'nsew')
        @app.command(:grid, :columnconfigure, path, 0, weight: 1)
        @app.command(:grid, :rowconfigure, path, 0, weight: 1)
      end

      # Tk's own `grid remove` un-maps a widget but (unlike `grid forget`)
      # remembers its grid options, so showing it again later is just a
      # bare `grid <path>` - no need to re-derive/re-pass row:/column:/
      # sticky: ourselves.
      #
      # Tk only re-invokes -yscrollcommand/-xscrollcommand when the
      # reported fraction actually *changes* - an empty widget that gains
      # a few rows can go straight from "0.0 1.0" (nothing to scroll) to
      # "0.0 1.0" again (still nothing to scroll), with the callback never
      # firing in between. That would leave the eagerly-gridded scrollbar
      # stuck shown forever, so #after_idle also checks the real, current
      # fraction directly (via a plain +yview+ query) once - after every
      # widget this build creates has gone through its first geometry
      # pass, same as the callback itself would eventually see.
      def auto_hide_scrollbar(target_path, scrollbar_path, option:)
        shown = true
        apply = lambda do |first, last|
          fits = first.to_f <= 0.0 && last.to_f >= 1.0
          if fits && shown
            @app.command(:grid, :remove, scrollbar_path)
            shown = false
          elsif !fits && !shown
            @app.command(:grid, scrollbar_path)
            shown = true
          end
        end

        @app.command(target_path, :configure, option => proc { |first, last|
          @app.command(scrollbar_path, :set, first, last)
          apply.call(first, last)
        })
        @app.after_idle {
          first, last = @app.command(target_path, :yview).split
          apply.call(first, last)
        }
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
      # -menu config / on_right_click wiring, never via pack/grid either;
      # :tab is placed entirely by `ttk::notebook add` (#setup_tab), not a
      # geometry manager at all; :pane likewise via `ttk::panedwindow add`
      # (#setup_pane).
      NOT_ARRANGED_TYPES = %i[raw_op window menu_bar context_menu tab pane].freeze

      def arrange_children(node)
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
          arrangeable.each { |child| @app.command(:pack, child.realized.arrange_path, fill: 'both', expand: true) }
        else
          arrangeable.each { |child| @app.command(:pack, child.realized.arrange_path) }
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
          @app.command(:pack, child.realized.arrange_path, **opts)
        end
      end

      def arrange_grid(node, children)
        gap = node.opts.fetch(:gap, 0)

        children.each do |child|
          cell = child.layout && child.layout[:cell]
          unless cell
            # {GridValidator.check_missing_cell} is the primary detection
            # for this now, pre-realize - this stays as a
            # belt-and-suspenders backstop for the one path that skips
            # validation entirely, {Session#add}'s incremental realize.
            raise ArgumentError, "#{describe(child)} is a direct child of a grid but was never placed with " \
                                  "g.cell(row:, col:) { ... }"
          end

          opts = { row: cell[:row], column: cell[:col], sticky: 'ew', padx: gap, pady: gap }
          opts[:columnspan] = cell[:span] if cell[:span].to_i > 1
          @app.command(:grid, child.realized.arrange_path, **opts)
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
