# frozen_string_literal: true

require_relative 'mouse_events'

module Teek
  module UI
    # A handle onto one or more canvas items, addressed by Tk's own
    # tagOrId - either the numeric id a `create` call returns (a single
    # item) or an arbitrary tag string (every item currently carrying it,
    # zero or more). Every method here is exactly that uniform - Tk's own
    # canvas command already treats a tag and an id identically for
    # move/coords/itemconfigure/delete/stacking/scale, so a shared tag is
    # addressable as a group with no separate "group handle" type: get one
    # via a shape-creation method (see {Handle#line} and friends, a
    # single-item handle) or {Handle#tagged} (an existing tag, whatever it
    # currently matches).
    class CanvasItem
      # @return [String] the tagOrId this handle addresses
      attr_reader :tag_or_id

      # @api private
      def initialize(app, canvas_path, tag_or_id)
        @app = app
        @canvas_path = canvas_path
        @tag_or_id = tag_or_id.to_s
      end

      # @return [String] the canvas's own path, marked past the point a
      #   real Tk path stops applying - an item/tag has no independent Tk
      #   path of its own, only the canvas does. +!+ is illegal in a Tk
      #   path segment, so handing this to a raw Tk command fails loudly
      #   (an "invalid command name" Tcl error) instead of silently
      #   misbehaving - the same marked-address shape
      #   {MenuEntryAddressing#virtual_path} uses for a menu entry, the
      #   other kind of thing with no Tk path of its own.
      def virtual_path
        "#{@canvas_path}!#{@tag_or_id}"
      end

      # Move relative to the current position.
      # @param dx [Numeric]
      # @param dy [Numeric]
      # @return [self]
      def move(dx, dy)
        @app.command(@canvas_path, :move, @tag_or_id, dx, dy)
        self
      end

      # @return [Array<Float>] the current coordinate list
      def coords
        result = @app.command(@canvas_path, :coords, @tag_or_id)
        @app.split_list(result).map(&:to_f)
      end

      # Replace the coordinate list outright (as opposed to {#move}'s
      # relative shift).
      # @param new_coords [Array<Numeric>] flat or nested (e.g.
      #   +[[x1, y1], [x2, y2]]+) - flattened either way
      # @return [void]
      def coords=(new_coords)
        @app.command(@canvas_path, :coords, @tag_or_id, *new_coords.flatten)
      end

      # Mutate several item options at once.
      # @param opts [Hash] item options, e.g. +fill: 'red'+
      # @return [self]
      def configure(**opts)
        @app.command(@canvas_path, :itemconfigure, @tag_or_id, **opts)
        self
      end

      # Read back a single item option - +item[:fill]+.
      # @param opt [Symbol, String] e.g. +:fill+
      # @return [String]
      def [](opt)
        @app.command(@canvas_path, :itemcget, @tag_or_id, "-#{opt}")
      end

      # Set a single item option - +item[:fill] = 'red'+. Shorthand for
      # +configure(opt => value)+ when there's only one to change.
      # @param opt [Symbol, String] e.g. +:fill+
      # @param value [Object]
      # @return [Object] +value+
      def []=(opt, value)
        configure(opt => value)
        value
      end

      # Remove the item(s) from the canvas.
      # @return [nil]
      def delete
        @app.command(@canvas_path, :delete, @tag_or_id)
        nil
      end

      # Bring to the front of the stacking order (drawn last, on top of
      # everything), or - given +above+ - just in front of that one
      # item/tag instead of all the way to the front.
      # @param above [CanvasItem, String, nil]
      # @return [self]
      def bring_to_front(above = nil)
        args = above ? [resolve(above)] : []
        @app.command(@canvas_path, :raise, @tag_or_id, *args)
        self
      end

      # Send to the back of the stacking order (drawn first, under
      # everything), or - given +below+ - just behind that one item/tag
      # instead of all the way to the back.
      # @param below [CanvasItem, String, nil]
      # @return [self]
      def send_to_back(below = nil)
        args = below ? [resolve(below)] : []
        @app.command(@canvas_path, :lower, @tag_or_id, *args)
        self
      end

      # Scale coordinates relative to a fixed point.
      # @param ox [Numeric] x origin scaling is relative to
      # @param oy [Numeric] y origin scaling is relative to
      # @param sx [Numeric] x scale factor
      # @param sy [Numeric] y scale factor
      # @return [self]
      def scale(ox, oy, sx, sy)
        @app.command(@canvas_path, :scale, @tag_or_id, ox, oy, sx, sy)
        self
      end

      # @return [Array<Float>, nil] +[x1, y1, x2, y2]+ bounding box, or
      #   +nil+ if nothing currently matches {#tag_or_id}
      def bounds
        result = @app.command(@canvas_path, :bbox, @tag_or_id)
        result.empty? ? nil : @app.split_list(result).map(&:to_f)
      end

      # @return [Boolean] whether any item currently matches {#tag_or_id} -
      #   always true for a single-item handle from a creation method
      #   (the item exists until {#delete}d), meaningful for a {Handle#tagged}
      #   group that may currently match zero items
      def exists?
        !@app.command(@canvas_path, :find, :withtag, @tag_or_id).empty?
      end

      # Fires on a left click, only when the click lands on this specific
      # item/tag - other items on the same canvas are untouched. Wired
      # immediately, via the canvas's own `bind` subcommand (Tk has no
      # per-item widget path to bind a plain `bind` against) - unlike
      # {Handle}, a CanvasItem only ever exists post-realize, so there's no
      # queue-before-realize phase to worry about here.
      # @yield called with no arguments
      # @return [self]
      def on_click(&block)
        bind_item_event('<Button-1>', block)
        self
      end

      # Fires on a right click, however the platform spells it - see
      # {MouseEvents::RIGHT_CLICK_EVENTS}. Either handle it yourself with a
      # block, or hand it a `:menu`/`:context_menu` handle to pop up at the
      # click's screen position - not both.
      # @param menu [Handle, nil] a `:menu` or `:context_menu` handle to tk_popup
      # @yield called with no arguments (only when +menu+ isn't given)
      # @return [self]
      # @raise [ArgumentError] if given neither or both, or +menu+ isn't a menu handle
      def on_right_click(menu = nil, &block)
        if menu && block
          raise ArgumentError, "on_right_click takes either a menu handle or a block, not both"
        elsif menu
          unless MouseEvents::MENU_HANDLE_TYPES.include?(menu.type)
            raise ArgumentError, "on_right_click(menu) needs a :menu or :context_menu handle (got a :#{menu.type})"
          end

          popup = lambda do |root_x, root_y|
            @app.popup_menu(menu.path, x: root_x, y: root_y)
          end
          MouseEvents::RIGHT_CLICK_EVENTS.each { |event| bind_item_event(event, popup, subs: %i[root_x root_y]) }
        elsif block
          MouseEvents::RIGHT_CLICK_EVENTS.each { |event| bind_item_event(event, block) }
        else
          raise ArgumentError, "on_right_click needs either a menu handle or a block"
        end
        self
      end

      # Fires while dragging this item (left button held down and moving).
      # Delivers Integer x/y already converted through the canvas's own
      # canvasx/canvasy, same as {Handle#on_drag} does when bound to a
      # canvas - callers never have to remember to do that themselves.
      # @yield [x, y] Integer coordinates
      # @return [self]
      def on_drag(&block)
        wrapped = lambda do |raw_x, raw_y|
          x, y = canvas_xy(raw_x, raw_y)
          block.call(x, y)
        end
        bind_item_event('<B1-Motion>', wrapped, subs: %i[x y])
        self
      end

      # Makes this item movable by mouse drag, with zero coordinate math
      # of your own - press and drag it around the canvas, it follows the
      # pointer. Binds `<Button-1>` (to capture the starting position) and
      # `<B1-Motion>` (to shift {#move} by the delta each tick) on this
      # item/tag, replacing any {#on_click}/{#on_drag} binding already set
      # on it, the same way any two binds on the same item/event replace
      # each other in Tk.
      # @yield [x, y] optional - the item's new pointer-relative position
      #   (same Integer canvasx/canvasy coordinates {#on_drag} delivers)
      #   after each move, e.g. to react to where it's been dragged to
      # @return [self]
      def draggable(&block)
        last = nil

        press = lambda do |raw_x, raw_y|
          last = canvas_xy(raw_x, raw_y)
        end
        bind_item_event('<Button-1>', press, subs: %i[x y])

        drag = lambda do |raw_x, raw_y|
          x, y = canvas_xy(raw_x, raw_y)
          move(x - last[0], y - last[1])
          last = [x, y]
          block.call(x, y) if block
        end
        bind_item_event('<B1-Motion>', drag, subs: %i[x y])

        self
      end

      private

      def canvas_xy(raw_x, raw_y)
        x = @app.command(@canvas_path, :canvasx, raw_x).to_f.round
        y = @app.command(@canvas_path, :canvasy, raw_y).to_f.round
        [x, y]
      end

      def resolve(item)
        item.is_a?(CanvasItem) ? item.tag_or_id : item.to_s
      end

      # Canvas items have no widget path of their own, so binding one of
      # their events goes through the canvas's own `bind` subcommand
      # (`$canvas bind tagOrId <event> script`) rather than the generic
      # `bind` Tk command {Teek::App#bind} wraps - a different Tcl command
      # entirely, needing its own callback wiring. {Teek::CanvasBindInterceptor}
      # (registered for the `canvas` widget type) already reconciles the
      # callback this registers when the item's tag/id stops matching
      # anything, same leak-safety {Teek::App#bind} gives ordinary widget
      # events - nothing extra to do here for that. +subs+ reuses
      # {Teek::App::BIND_SUBS} for the same symbol -> %-code vocabulary
      # {Teek::App#bind} already uses, so e.g. +:x+/+:root_x+ mean the same
      # thing here as everywhere else.
      def bind_item_event(event, handler, subs: [])
        tcl_subs = subs.map { |s| Teek::App::BIND_SUBS.fetch(s) }
        @app.command(@canvas_path, :bind, @tag_or_id, event, proc { |*args| handler.call(*args) }, *tcl_subs)
      end
    end
  end
end
