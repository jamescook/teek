# frozen_string_literal: true

module Teek
  module MGBA
    # Renders inverse-blend HUD overlays (FPS counter, fast-forward indicator)
    # on top of the game viewport.
    #
    # White source pixels invert the destination, so the text is always
    # readable regardless of the game's background color. Transparent
    # regions pass through unchanged.
    #
    # @example
    #   hud = OverlayRenderer.new(font: font, blend_mode: inverse_blend)
    #   hud.set_fps("59.7 FPS")
    #   hud.set_ff_label(">> 2x")
    #   # inside render loop:
    #   hud.draw(r, dest_rect)
    class OverlayRenderer
      # @param font [Teek::SDL2::Font] used to render overlay text
      # @param blend_mode [Integer] SDL blend mode (typically inverse blend)
      def initialize(font:, blend_mode:)
        @font = font
        @blend_mode = blend_mode
        @crop_h = compute_crop_h(font)
        @fps_tex = nil
        @ff_tex = nil
      end

      # Update the FPS counter text. Pass nil to hide.
      # @param text [String, nil]
      def set_fps(text)
        @fps_tex&.destroy
        @fps_tex = text ? build_tex(text) : nil
      end

      # Update the fast-forward indicator label. Pass nil to hide.
      # @param text [String, nil]
      def set_ff_label(text)
        @ff_tex&.destroy
        @ff_tex = text ? build_tex(text) : nil
      end

      # Whether the FPS overlay is currently showing.
      # @return [Boolean]
      def fps_visible?
        !!@fps_tex
      end

      # Whether the fast-forward label is currently showing.
      # @return [Boolean]
      def ff_visible?
        !!@ff_tex
      end

      # Draw all active overlays.
      #
      # FPS is positioned top-right; FF label is positioned top-left.
      # Both are inset from the game area defined by +dest+.
      #
      # @param r [Teek::SDL2::Renderer]
      # @param dest [Array(Integer,Integer,Integer,Integer), nil] game area rect
      # @param show_fps [Boolean] whether to draw the FPS counter
      # @param show_ff [Boolean] whether to draw the FF indicator
      def draw(r, dest, show_fps: true, show_ff: false)
        if show_ff && @ff_tex
          ox = dest ? dest[0] : 0
          oy = dest ? dest[1] : 0
          draw_tex(r, @ff_tex, ox + 4, oy + 4)
        end

        if show_fps && @fps_tex
          fx = (dest ? dest[0] + dest[2] : r.output_size[0]) - @fps_tex.width - 6
          fy = (dest ? dest[1] : 0) + 4
          draw_tex(r, @fps_tex, fx, fy)
        end
      end

      # Free all textures.
      def destroy
        @fps_tex&.destroy
        @fps_tex = nil
        @ff_tex&.destroy
        @ff_tex = nil
      end

      private

      def build_tex(text)
        return nil unless @font
        tex = @font.render_text(text, 255, 255, 255)
        tex.blend_mode = @blend_mode
        tex
      end

      # Crop to ascent + partial descender to avoid alpha artifacts
      # visible under inverse blending.
      def draw_tex(r, tex, x, y)
        tw = tex.width
        th = @crop_h || tex.height
        r.copy(tex, [0, 0, tw, th], [x, y, tw, th])
      end

      def compute_crop_h(font)
        return nil unless font
        ascent = font.ascent
        full_h = font.measure('p')[1]
        [ascent + (full_h - ascent) / 2, full_h - 1].min
      end
    end
  end
end
