# frozen_string_literal: true

module Teek
  module MGBA
    # Click-to-show tooltip service for Tk widgets.
    #
    # Labels registered with {#register} get an underlined font (like HTML
    # <abbr>). Clicking them shows a tooltip popup below the label. Only one
    # tooltip is visible at a time; it auto-dismisses after {#dismiss_ms}
    # unless the mouse hovers over the tip or its label.
    #
    # The tooltip is rendered as a frame inside the parent window (not a
    # toplevel), so it draws as a true rectangle on all platforms.
    #
    # @example
    #   tips = TipService.new(app, parent: '.settings')
    #   tips.register('.settings.nb.video.lbl_color', 'Adjusts GBA LCD colors')
    class TipService
      DEFAULT_DISMISS_MS = 4000

      # Tooltip colors (pale yellow with gray border, dark text)
      TIP_BG      = '#FFFFEE'
      TIP_FG      = '#333333'
      TIP_BORDER  = '#999999'

      # @param app [Teek::App]
      # @param parent [String] parent Toplevel path (for unique tooltip path)
      # @param dismiss_ms [Integer] auto-dismiss delay in milliseconds
      def initialize(app, parent: '.', dismiss_ms: DEFAULT_DISMISS_MS)
        @app = app
        @parent = parent
        @tip_path = parent == '.' ? '.__tip' : "#{parent}.__tip"
        @dismiss_ms = dismiss_ms
        @target = nil
        @timer = nil
        @click_guard = false

        # Underlined font for registered labels
        @font_name = "__tip_font_#{parent.tr('.', '_')}"
        @app.tcl_eval("catch {font create #{@font_name} {*}[font actual TkDefaultFont] -underline 1}")

        # Click anywhere in the parent window dismisses the tooltip,
        # unless the click was on a registered label (guard prevents that).
        @app.command(:bind, @parent, '<Button-1>', proc {
          if @click_guard
            @click_guard = false
          elsif showing?
            hide
          end
        })
      end

      # @return [Integer] auto-dismiss delay in milliseconds
      attr_accessor :dismiss_ms

      # @return [String, nil] widget path of the currently showing tip's label
      attr_reader :target

      # Register a widget for click-to-show tooltip.
      # @param widget_path [String] Tk widget path (typically a label)
      # @param text [String] tooltip text (may contain \n for line breaks)
      def register(widget_path, text)
        @app.command(widget_path, 'configure', font: @font_name)
        @app.command(:bind, widget_path, '<Button-1>', proc { toggle(widget_path, text) })
        @app.command(:bind, widget_path, '<Enter>', proc { cancel_dismiss })
        @app.command(:bind, widget_path, '<Leave>', proc { schedule_dismiss })
      end

      # Show a tooltip below the given widget. Hides any existing tip first.
      # @param widget_path [String]
      # @param text [String]
      def show(widget_path, text)
        hide

        @target = widget_path

        # Position relative to the parent toplevel
        lx, ly, _lw, lh = @app.interp.window_geometry(widget_path)
        px, py, _pw, _ph = @app.interp.window_geometry(@parent)
        rel_x = lx - px
        rel_y = ly - py + lh + 4

        # Border frame (1px border effect via padding)
        @app.command(:frame, @tip_path, background: TIP_BORDER, borderwidth: 0)

        @app.command(:label, "#{@tip_path}.l",
          text: text, background: TIP_BG, foreground: TIP_FG,
          padx: 8, pady: 6, justify: :left)
        @app.command(:pack, "#{@tip_path}.l", padx: 1, pady: 1)

        @app.command(:place, @tip_path, x: rel_x, y: rel_y)
        @app.command(:raise, @tip_path)

        # Pause auto-dismiss while hovering the tooltip itself
        @app.command(:bind, @tip_path, '<Enter>', proc { cancel_dismiss })
        @app.command(:bind, @tip_path, '<Leave>', proc { schedule_dismiss })
      end

      # Hide the current tooltip.
      def hide
        cancel_dismiss
        @target = nil
        @app.tcl_eval("catch {destroy #{@tip_path}}")
      end

      # @return [Boolean] true if a tooltip is currently visible
      def showing?
        !!@target
      end

      private

      def toggle(widget_path, text)
        @click_guard = true
        if @target == widget_path
          hide
        else
          show(widget_path, text)
        end
      end

      def schedule_dismiss
        cancel_dismiss
        @timer = @app.after(@dismiss_ms) { hide }
      end

      def cancel_dismiss
        if @timer
          @app.command(:after, :cancel, @timer)
          @timer = nil
        end
      end
    end
  end
end
