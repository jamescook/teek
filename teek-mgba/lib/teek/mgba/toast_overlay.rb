# frozen_string_literal: true

module Teek
  module MGBA
    # Renders timed notification toasts at the bottom of the game viewport.
    #
    # One toast at a time; showing a new one replaces the old. The background
    # is a pre-rendered anti-aliased rounded rectangle (generated in C).
    #
    # All SDL2 objects (renderer, font, textures) are injected or created
    # internally, so the class can be tested with lightweight mocks.
    #
    # @example
    #   toast = ToastOverlay.new(renderer: vp.renderer, font: font, duration: 1.5)
    #   toast.show("State saved to slot 1")
    #   # inside render loop:
    #   toast.draw(r, dest_rect)
    class ToastOverlay
      PAD_X  = 14
      PAD_Y  = 8
      RADIUS = 8

      # @param renderer [Teek::SDL2::Renderer] creates background textures
      # @param font [Teek::SDL2::Font] renders toast text
      # @param duration [Float] default display time in seconds
      # @param bg_fn [#call] generates ARGB pixel data for the rounded-rect
      #   background; signature: bg_fn.call(w, h, radius) → String.
      #   Defaults to the C-implemented {Teek::MGBA.toast_background}.
      def initialize(renderer:, font:, duration: 1.5, bg_fn: Teek::MGBA.method(:toast_background))
        @renderer = renderer
        @font = font
        @duration = duration
        @bg_fn = bg_fn
        @crop_h = compute_crop_h(font)
        @bg_tex = nil
        @text_tex = nil
      end

      # @return [Float] default display duration in seconds
      attr_accessor :duration

      # Whether a toast is currently visible.
      # @return [Boolean]
      def visible?
        !!@bg_tex
      end

      # Display a toast message. Replaces any existing toast.
      #
      # @param message [String]
      # @param duration [Float, nil] seconds; nil uses the default
      # @param permanent [Boolean] stays until {#destroy} is called
      def show(message, duration: nil, permanent: false)
        destroy

        @text_tex = @font.render_text(message, 255, 255, 255)
        tw = @text_tex.width
        th = @crop_h || @text_tex.height

        box_w = tw + PAD_X * 2
        box_h = th + PAD_Y * 2

        bg_pixels = @bg_fn.call(box_w, box_h, RADIUS)
        @bg_tex = @renderer.create_texture(box_w, box_h, :streaming)
        @bg_tex.update(bg_pixels)
        @bg_tex.blend_mode = :blend

        @box_w = box_w
        @box_h = box_h
        @text_w = tw
        @text_h = th
        @permanent = permanent
        @expires = permanent ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC) + (duration || @duration)
      end

      # Draw the toast centered at the bottom of the game area.
      #
      # @param r [Teek::SDL2::Renderer]
      # @param dest [Array(Integer,Integer,Integer,Integer), nil] game area rect
      def draw(r, dest)
        return unless @bg_tex
        unless @permanent
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if now >= @expires
            destroy
            return
          end
        end

        # Position: bottom-center of game area, 12px from bottom
        if dest
          cx = dest[0] + dest[2] / 2
          by = dest[1] + dest[3] - 12 - @box_h
        else
          out_w, out_h = r.output_size
          cx = out_w / 2
          by = out_h - 12 - @box_h
        end
        bx = cx - @box_w / 2

        # Background (pre-rendered with AA rounded corners)
        r.copy(@bg_tex, nil, [bx, by, @box_w, @box_h])
        # White text centered in the box
        tx = bx + (@box_w - @text_w) / 2
        ty = by + (@box_h - @text_h) / 2
        r.copy(@text_tex, [0, 0, @text_w, @text_h],
               [tx, ty, @text_w, @text_h])
      end

      # Remove the current toast and free textures.
      def destroy
        @bg_tex&.destroy
        @bg_tex = nil
        @text_tex&.destroy
        @text_tex = nil
      end

      private

      # Crop height: ascent + partial descender. Excludes the very bottom
      # rows where TTF anti-alias residue causes visible white-line artifacts.
      def compute_crop_h(font)
        return nil unless font
        ascent = font.ascent
        full_h = font.measure('p')[1]
        [ascent + (full_h - ascent) / 2, full_h - 1].min
      end
    end
  end
end
