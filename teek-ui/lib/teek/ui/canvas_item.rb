# frozen_string_literal: true

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

      private

      def resolve(item)
        item.is_a?(CanvasItem) ? item.tag_or_id : item.to_s
      end
    end
  end
end
