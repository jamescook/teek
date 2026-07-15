# frozen_string_literal: true

require_relative 'errors'
require_relative 'realized_node'
require_relative 'event_binding'
require_relative 'keysyms'
require_relative 'mouse_events'
require_relative 'canvas_item'
require_relative 'widget_addressing'
require_relative 'widget_types'
require_relative 'realizer'

module Teek
  module UI
    # The single handle type for a node, valid across both phases (Resolved
    # decision #3 in the architecture doc - no separate build-time NodeRef).
    # During build you compose/name/record-events on it; live methods
    # (#path, #configure) raise {NotRealizedError} until the node's
    # +realized+ slot is filled in by the realizer, then the same Handle
    # object drives the real widget through it.
    class Handle
      RIGHT_CLICK_EVENTS = MouseEvents::RIGHT_CLICK_EVENTS
      MENU_HANDLE_TYPES = MouseEvents::MENU_HANDLE_TYPES

      # @api private
      def initialize(node)
        @node = node
        @addressing = (WidgetTypes.for_type(node.type)&.addressing || WidgetAddressing).new(node)
      end

      # @return [Symbol] the node's type, e.g. +:button+
      def type
        @node.type
      end

      # @return [Symbol, nil] the node's explicit name
      def name
        @node.name
      end

      # @return [String] this node's live address - the real Tk widget
      #   path for an ordinary widget, or (for a type with none of its
      #   own, e.g. a menu entry) its {WidgetType#addressing} strategy's
      #   own marked, Tk-path-shaped virtual path - see
      #   {MenuEntryAddressing#virtual_path}
      # @raise [NotRealizedError] before realize
      def path
        @addressing.virtual_path
      end

      # @return [Teek::App] the underlying app this widget was realized into
      # @raise [NotRealizedError] before realize
      def app
        realized.app
      end

      # Mutate the live widget's (or, for a type with none of its own,
      # e.g. a menu entry - the entry's own) options - delegated entirely
      # to this node type's {WidgetType#addressing} strategy, so Handle
      # itself carries no per-type knowledge of how to reach it.
      # @param opts [Hash] e.g. +text: "Go"+
      # @raise [NotRealizedError] before realize
      def configure(**opts)
        @addressing.configure(**opts)
      end

      # What Tk currently thinks this widget's (or, for a type with none
      # of its own, e.g. a menu entry - the entry's own) options are right
      # now, straight from a bare +configure+ - for when a prior
      # {#configure} call seems like it silently didn't take, or just
      # exploring what's actually set on a live widget. Delegated to this
      # node type's {WidgetType#addressing} strategy, same as {#configure}.
      # @return [Hash{Symbol => String}] option name (no leading +-+) => current value
      # @raise [NotRealizedError] before realize
      def options
        @addressing.option_dump
      end

      # Shorthand for +configure(state: :normal)+ - Tk's own default
      # state, meaningful for anything with a +-state+ option (a menu
      # entry, a ttk widget, ...).
      # @return [self]
      # @raise [NotRealizedError] before realize
      def enable
        configure(state: :normal)
        self
      end

      # Shorthand for +configure(state: :disabled)+ - greyed out, not
      # interactive/invocable.
      # @return [self]
      # @raise [NotRealizedError] before realize
      def disable
        configure(state: :disabled)
        self
      end

      # Tears down this node's live widget (and everything under it),
      # releasing its callbacks via teek's existing +<Destroy>+ cleanup,
      # and resets it so a later push of a fresh mount rebuilds it from
      # scratch. The rebuild gets a fresh Tk path, not necessarily this
      # same one - path segments are claimed once and never recycled (see
      # {Document#claim_path_segment}), so this stays safe even if another
      # instance sharing this same local name is still alive elsewhere
      # under the same parent. Typically called after popping a screen you
      # don't want to keep warm (see {Screens}) - popping alone only
      # conceals, exactly as before; this is a separate, explicit step -
      # +ui.screens.pop&.destroy!+/+ui.modal.pop&.destroy!+.
      #
      # Destroying a widget SYNCHRONOUSLY from inside the click handler
      # of one of its own descendants (a dialog's own "Close" button
      # tearing down the dialog it lives in) is a real Tk hazard:
      # `ttk::button` (and others) queue their own internal bindings for
      # that SAME click, which then run against a widget that's already
      # gone. +defer+ absorbs this automatically - no need to know about
      # it or reach for `ui.after` yourself.
      # @param defer [Boolean, nil] +nil+ (the default) auto-detects:
      #   defers to the next Tk idle point ({Teek.in_callback?} true -
      #   the hazard above) so the current click finishes first, or
      #   destroys synchronously otherwise (a script/test with no event
      #   loop running has nothing to defer TO, and wants "gone when
      #   this call returns" semantics). Pass explicitly to override
      #   either way. Calling this again on the same handle while its
      #   own deferred destroy hasn't run yet is a safe no-op.
      #
      #   The one residual to know about: when this DOES defer, it
      #   returns before the widget is actually gone - the node still
      #   reports realized and its old Tk path still exists until the
      #   deferred teardown runs. Don't +destroy!+ then immediately
      #   rebuild a fresh mount at that SAME name/path in the same
      #   handler expecting the old one to already be gone; either pass
      #   +defer: false+ to force it synchronous first, or build the
      #   replacement under a genuinely distinct mount (the normal
      #   "fresh `lazy: true` component per open" pattern already does
      #   this, since {Document#claim_path_segment} never reuses a path
      #   segment anyway).
      # @return [nil]
      # @raise [NotRealizedError] if this node was never realized
      def destroy!(defer: nil)
        return nil if @node.pending_destroy?

        should_defer = defer.nil? ? Teek.in_callback? : defer
        if should_defer
          app = realized.app
          @node.pending_destroy = true
          app.after_idle { perform_destroy! }
        else
          perform_destroy!
        end
        nil
      end

      # Fires on a left click.
      # @yield called with no arguments
      # @return [self]
      def on_click(&block)
        bind_event('<Button-1>', block)
        self
      end

      # Fires on a right click, however the platform spells it (Button-3 on
      # Linux/Windows, Button-2 or Control-Button-1 on macOS). Either handle
      # it yourself with a block, or hand it a `:menu`/`:context_menu`
      # handle to pop up at the click's screen position - not both.
      # @param menu [Handle, nil] a `:menu` or `:context_menu` handle to tk_popup
      # @yield called with no arguments (only when +menu+ isn't given)
      # @return [self]
      # @raise [ArgumentError] if given neither or both, or +menu+ isn't a menu handle
      def on_right_click(menu = nil, &block)
        if menu && block
          raise ArgumentError, "on_right_click takes either a menu handle or a block, not both"
        elsif menu
          unless MENU_HANDLE_TYPES.include?(menu.type)
            raise ArgumentError, "on_right_click(menu) needs a :menu or :context_menu handle (got a :#{menu.type})"
          end

          popup = lambda do |root_x, root_y|
            realized.app.popup_menu(menu.path, x: root_x, y: root_y)
          end
          RIGHT_CLICK_EVENTS.each { |event| bind_event(event, popup, subs: %i[root_x root_y]) }
        elsif block
          RIGHT_CLICK_EVENTS.each { |event| bind_event(event, block) }
        else
          raise ArgumentError, "on_right_click needs either a menu handle or a block"
        end
        self
      end

      # Fires while dragging (left button held down and moving). Delivers
      # Integer x/y, converted through the widget's own canvasx/canvasy when
      # bound to a canvas so callers never have to remember to do that
      # themselves.
      # @yield [x, y] Integer coordinates
      # @return [self]
      def on_drag(&block)
        drag_type = type
        wrapped = lambda do |raw_x, raw_y|
          block.call(*convert_drag_coords(drag_type, raw_x, raw_y))
        end
        bind_event('<B1-Motion>', wrapped, subs: %i[x y])
        self
      end

      # Fires on a key press. +spec+ is either a friendly Symbol (+:enter+,
      # +:escape+, +:up+, ...) or a "Modifier-Modifier-Key" String
      # (+"Ctrl-s"+, +"Ctrl-Shift-s"+) - see {Keysyms}.
      # @param spec [Symbol, String]
      # @yield called with no arguments
      # @return [self]
      def on_key(spec, &block)
        modifiers, keysym = Keysyms.resolve(spec)
        Keysyms.patterns_for(modifiers, keysym).each { |event| bind_event(event, block) }
        self
      end

      # Fires when the window's close button (titlebar close box, Cmd-W,
      # Alt-F4, ...) is pressed. Teek's own default (destroy the window)
      # only applies when nothing else has claimed it - the block decides
      # whether the window actually closes; call `.destroy` yourself if you
      # want that. Only valid on a `ui.window` handle.
      # @yield called with no arguments
      # @return [self]
      # @raise [ArgumentError] if this handle isn't a window
      def on_close(&block)
        unless type == :window
          raise ArgumentError, "on_close only makes sense on a window (got a :#{type})"
        end

        if @node.realized
          @node.realized.app.on_close(window: @node.realized.path, &block)
        else
          @node.opts[:on_close] = block
        end
        self
      end

      # Fires when the selected tab changes (Tk's <<NotebookTabChanged>>).
      # The block receives the newly selected tab's own name (the Symbol
      # given via `t.tab(label, name)`) if it has one, otherwise its plain
      # zero-based index - preferring a name over a raw Tk index, same as
      # `ui[:name]` lookup does everywhere else in the DSL. Only valid on a
      # `ui.tabs` handle.
      # @yield [name_or_index] Symbol or Integer
      # @return [self]
      # @raise [ArgumentError] if this handle isn't a tabs container
      def on_tab_changed(&block)
        unless type == :tabs
          raise ArgumentError, "on_tab_changed only makes sense on a tabs container (got a :#{type})"
        end

        wrapped = lambda {
          index = realized.app.command(realized.path, :index, :current).to_i
          tab_node = @node.children[index]
          block.call(tab_node&.name || index)
        }
        bind_event('<<NotebookTabChanged>>', wrapped)
        self
      end

      # Show the window modally: grabs input and sets focus on it
      # immediately. Release it explicitly with {#grab_release} (typically
      # from the window's own dismiss/close handling) when the dialog is
      # done - not released automatically just because this method
      # returns, since a modal dialog stays grabbed for its whole visible
      # lifetime, not just its setup. Released immediately if the optional
      # setup block itself raises, or if the window is destroyed while
      # still grabbed - see {Teek::Window#modal}, which this delegates to
      # entirely (no grab/focus/destroy-safety-net logic lives here).
      # Only valid on a `ui.window` handle.
      # @param global [Boolean] see {Teek::Window#grab_set}
      # @yield optional - runs with the grab and focus already set
      # @return [void]
      # @raise [ArgumentError] if this handle isn't a window
      # @raise [NotRealizedError] before realize
      def modal(global: false, &block)
        unless type == :window
          raise ArgumentError, "modal only makes sense on a window (got a :#{type})"
        end

        window.modal(global: global, &block)
      end

      # Release a grab previously set with {#modal}. Only valid on a
      # `ui.window` handle. See {Teek::Window#grab_release}.
      # @return [void]
      # @raise [ArgumentError] if this handle isn't a window
      # @raise [NotRealizedError] before realize
      def grab_release
        unless type == :window
          raise ArgumentError, "grab_release only makes sense on a window (got a :#{type})"
        end

        window.grab_release
      end

      # Reveal the window: positions it just to the right of the parent
      # it's nested under (root, or another window if this one's nested
      # inside it), deiconifies, raises it to the front, and - only if
      # this window was declared `modal: true` - grabs input and focuses
      # it too (via {#modal}). Only valid on a `ui.window` handle.
      # @return [self]
      # @raise [ArgumentError] if this handle isn't a window
      # @raise [NotRealizedError] before realize
      def show
        unless type == :window
          raise ArgumentError, "show only makes sense on a window (got a :#{type})"
        end

        position_near_parent
        window.deiconify
        realized.app.command(:raise, realized.path)
        modal if @node.opts[:modal]
        self
      end

      # Hide the window: releases any grab {#show} set (a no-op if it
      # wasn't modal - {Teek::Window#grab_release} is always safe to call)
      # and withdraws it. Only valid on a `ui.window` handle.
      # @return [self]
      # @raise [ArgumentError] if this handle isn't a window
      # @raise [NotRealizedError] before realize
      def hide
        unless type == :window
          raise ArgumentError, "hide only makes sense on a window (got a :#{type})"
        end

        grab_release
        window.withdraw
        self
      end

      # A straight line through the given points - +[x1, y1, x2, y2, ...]+,
      # flat or nested, two or more points. Only valid on a `ui.canvas` handle.
      # @param coords [Array<Numeric>]
      # @param opts [Hash] item options, e.g. +fill:+/+width:+/+tags:+
      # @return [CanvasItem]
      # @raise [ArgumentError] if this handle isn't a canvas
      # @raise [NotRealizedError] before realize
      def line(*coords, **opts)
        create_canvas_item(:line, coords, opts)
      end

      # An oval inscribed in the bounding box +[x1, y1, x2, y2]+. Only
      # valid on a `ui.canvas` handle.
      # @param coords [Array<Numeric>]
      # @param opts [Hash] item options, e.g. +fill:+/+outline:+/+tags:+
      # @return [CanvasItem]
      # @raise [ArgumentError] if this handle isn't a canvas
      # @raise [NotRealizedError] before realize
      def oval(*coords, **opts)
        create_canvas_item(:oval, coords, opts)
      end

      # A closed shape through the given points - +[x1, y1, x2, y2, ...]+,
      # flat or nested, three or more points. Only valid on a `ui.canvas` handle.
      # @param coords [Array<Numeric>]
      # @param opts [Hash] item options, e.g. +fill:+/+smooth:+/+tags:+
      # @return [CanvasItem]
      # @raise [ArgumentError] if this handle isn't a canvas
      # @raise [NotRealizedError] before realize
      def polygon(*coords, **opts)
        create_canvas_item(:polygon, coords, opts)
      end

      # A rectangle with corners +[x1, y1, x2, y2]+. Only valid on a
      # `ui.canvas` handle.
      # @param coords [Array<Numeric>]
      # @param opts [Hash] item options, e.g. +fill:+/+outline:+/+tags:+
      # @return [CanvasItem]
      # @raise [ArgumentError] if this handle isn't a canvas
      # @raise [NotRealizedError] before realize
      def rectangle(*coords, **opts)
        create_canvas_item(:rectangle, coords, opts)
      end

      # Text anchored at +[x, y]+. Only valid on a `ui.canvas` handle.
      # @param coords [Array<Numeric>] a single +[x, y]+ point
      # @param opts [Hash] item options, e.g. +text:+/+fill:+/+font:+/+anchor:+/+tags:+
      # @return [CanvasItem]
      # @raise [ArgumentError] if this handle isn't a canvas
      # @raise [NotRealizedError] before realize
      def text(*coords, **opts)
        create_canvas_item(:text, coords, opts)
      end

      # An arc/pie-slice/chord along the oval inscribed in the bounding
      # box +[x1, y1, x2, y2]+. Only valid on a `ui.canvas` handle.
      # @param coords [Array<Numeric>]
      # @param opts [Hash] item options, e.g. +start:+/+extent:+/+style:+/+tags:+
      # @return [CanvasItem]
      # @raise [ArgumentError] if this handle isn't a canvas
      # @raise [NotRealizedError] before realize
      def arc(*coords, **opts)
        create_canvas_item(:arc, coords, opts)
      end

      # A stipple bitmap anchored at +[x, y]+. Only valid on a `ui.canvas` handle.
      # @param coords [Array<Numeric>] a single +[x, y]+ point
      # @param opts [Hash] item options, e.g. +bitmap:+/+foreground:+/+tags:+
      # @return [CanvasItem]
      # @raise [ArgumentError] if this handle isn't a canvas
      # @raise [NotRealizedError] before realize
      def bitmap(*coords, **opts)
        create_canvas_item(:bitmap, coords, opts)
      end

      # Every event binding declared on this node so far, in declaration
      # order - +on_click+/+on_key+/+on_drag+/+on_right_click+ and
      # friends all funnel through here. Meaningful at any phase: before
      # realize these are still queued (nothing wired to Tcl yet), after
      # realize they're the bindings actually in effect - covers both a
      # binding declared in the original build block and one added later
      # (e.g. from inside {Session#add}), so this stays a true live
      # picture, not just a record of what was queued pre-realize. Each
      # entry's own +handler+ is the real Proc that runs, so
      # +.source_location+ answers "what code does this" directly.
      # @return [Array<EventBinding>]
      def events
        @node.events
      end

      # A handle onto whatever items currently carry +tag+ - zero, one, or
      # many (see {CanvasItem}, which addresses a tag and an id
      # identically). Doesn't create anything; a shape-creation method
      # (e.g. {#line}) already returns a single-item handle for its own
      # new item, this is for addressing a shared +tags:+ group (or
      # reaching an item by an id you already have) after the fact. Only
      # valid on a `ui.canvas` handle.
      # @param tag [String, Symbol, Integer]
      # @return [CanvasItem]
      # @raise [ArgumentError] if this handle isn't a canvas
      # @raise [NotRealizedError] before realize
      def tagged(tag)
        raise_unless_canvas!('tagged')
        CanvasItem.new(realized.app, realized.path, tag)
      end

      private

      def realized
        @node.realized or raise NotRealizedError
      end

      # The actual teardown {#destroy!} defers or runs immediately -
      # clears the pending flag first so a LATER, genuinely fresh
      # destroy! (after a rebuild) is never mistaken for a still-pending
      # one. Unlinks the node from the retained tree afterward (see
      # #unlink!) so it stops being reachable at all, not just Tk-dead.
      def perform_destroy!
        @node.pending_destroy = false
        realized.app.destroy(realized.path)
        @node.realized = nil
        unlink!
      end

      # Removes this node (and every named descendant of its own
      # subtree - Tk destroys descendants recursively, so their names
      # need to stop resolving too) from {Document}'s name index, then
      # removes the node itself from its own parent's +children+. Both
      # steps are plain Ruby, safe to run even if +@node.document+ is
      # nil (a raw +Node.new+ built directly, mostly in headless tests)
      # or +@node.parent+ is nil (already unlinked, or never attached).
      def unlink!
        document = @node.document
        @node.each { |descendant| document.unregister(descendant) } if document
        @node.parent&.remove_child(@node)
      end

      # @return [Boolean] whether this node has a live Tk widget yet -
      #   true for any ordinary handle once the tree's been realized;
      #   only ever false past that point for a +lazy: true+ container
      #   (see {WidgetDSL#append_container}) not yet {#realize!}d, or
      #   one that's been {#destroy!}ed since. Internal - {Screens#push}/
      #   {ModalStack#push} are what actually decide when to realize a
      #   lazy screen; an app author never needs to check this directly.
      def realized?
        !@node.realized.nil?
      end

      # Realizes this node (and everything declared inside it) into a
      # live Tk widget, if it isn't already - the on-demand counterpart
      # to +lazy: true+. A no-op if already realized. This node's own
      # {Node#parent} must already be realized (true for anything
      # reachable from an already-running app, which is the only
      # situation a lazy node is realized from). Internal - called via
      # +send+ by {Screens#push}/{ModalStack#push} (the only intended
      # callers); a +lazy: true+ screen "just works" through them, with
      # nothing for an app author to trigger by hand.
      # @param document [Document] the same {Document} this node belongs
      #   to - needed to resolve any +target:+ event bindings by name
      # @return [self]
      # @raise [NotRealizedError] if this node's own parent isn't realized yet
      def realize!(document)
        return self if realized?

        parent_node = @node.parent
        parent_realized = parent_node&.realized or
          raise NotRealizedError, "can't realize this node - its own parent isn't realized yet"

        Realizer.new(parent_realized.app, document).realize_subtree(@node, parent_node)
        self
      end

      def window
        realized.app.window(realized.path)
      end

      def create_canvas_item(shape, coords, opts)
        raise_unless_canvas!(shape)
        id = realized.app.command(realized.path, :create, shape, *coords.flatten, **opts)
        CanvasItem.new(realized.app, realized.path, id)
      end

      def raise_unless_canvas!(method_name)
        unless type == :canvas
          raise ArgumentError, "##{method_name} only makes sense on a canvas (got a :#{type})"
        end
      end

      # Positions the window just to the right of the parent it's nested
      # under - root by default, or another window's own path when this
      # one is declared inside it. Tk toplevel paths stay hierarchical
      # even though they're independent OS windows (allocate_path nests
      # them the same way any other widget path nests), so the parent's
      # path is just everything before this window's own last path
      # segment - no separate bookkeeping needed to recover it later.
      def position_near_parent
        parent_x, parent_y, parent_width, = realized.app.interp.window_geometry(toplevel_parent_path)
        window.set_geometry("+#{parent_x + parent_width + 12}+#{parent_y}")
      end

      def toplevel_parent_path
        path = realized.path
        last_dot = path.rindex('.')
        last_dot && last_dot.positive? ? path[0...last_dot] : '.'
      end

      def bind_event(event, handler, subs: [])
        binding = EventBinding.new(event: event, handler: handler, subs: subs)
        @node.events << binding
        wire(@node.realized, binding) if @node.realized
      end

      def wire(realized_node, binding)
        realized_node.app.bind(realized_node.path, binding.event, *binding.subs) { |*args|
          binding.handler.call(*args)
        }
      end

      def convert_drag_coords(drag_type, raw_x, raw_y)
        if drag_type == :canvas
          info = @node.realized
          x = info.app.command(info.path, :canvasx, raw_x).to_f.round
          y = info.app.command(info.path, :canvasy, raw_y).to_f.round
          [x, y]
        else
          [raw_x.to_i, raw_y.to_i]
        end
      end
    end
  end
end
