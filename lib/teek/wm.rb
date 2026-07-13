# frozen_string_literal: true

module Teek
  # Thin, typed wrapper around Tk's `wm` (window manager) command family -
  # one method per subcommand, coerced to the right Ruby type, reached via
  # {App#wm}. Kept for callers already using +app.wm.title(window: ...)+ -
  # every method here is a one-line delegate to {Window}, which is where
  # the actual `wm`/`grab` work now lives (see {Window}'s own doc comment
  # for why - the same window-scoped operations kept growing as more and
  # more +window:+-kwarg methods flattened onto {App}).
  #
  # @note Prefer +app.window(path)+ for new code - the same calls, without
  #   repeating +window:+ on every one when you're working with one window
  #   repeatedly.
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/wm.htm wm
  class Wm
    # @api private
    def initialize(app)
      @app = app
    end

    # @param window [String, Widget] (default: the root window)
    # @return [String] the window's current title
    def title(window: '.')
      @app.window(window).title
    end

    # @param value [String] new title
    # @param window [String, Widget] (default: the root window)
    # @return [String] the title
    def set_title(value, window: '.')
      @app.window(window).set_title(value)
    end

    # @param window [String, Widget] (default: the root window)
    # @return [String] geometry string (e.g. +"400x300+0+0"+)
    def geometry(window: '.')
      @app.window(window).geometry
    end

    # @param value [String] new geometry (e.g. +"400x300"+, +"400x300+100+50"+)
    # @param window [String, Widget] (default: the root window)
    # @return [String] the geometry
    def set_geometry(value, window: '.')
      @app.window(window).set_geometry(value)
    end

    # @param window [String, Widget] (default: the root window)
    # @return [Array(Boolean, Boolean)] [width_resizable, height_resizable]
    def resizable(window: '.')
      @app.window(window).resizable
    end

    # @param width [Boolean] allow horizontal resize
    # @param height [Boolean] allow vertical resize
    # @param window [String, Widget] (default: the root window)
    # @return [void]
    def set_resizable(width, height, window: '.')
      @app.window(window).set_resizable(width, height)
    end

    # Show a window (map it if withdrawn/iconified).
    # @param window [String, Widget] (default: the root window)
    # @return [void]
    def deiconify(window: '.')
      @app.window(window).deiconify
    end

    # Hide a window without destroying it.
    # @param window [String, Widget] (default: the root window)
    # @return [void]
    def withdraw(window: '.')
      @app.window(window).withdraw
    end
  end
end
