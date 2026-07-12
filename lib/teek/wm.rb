# frozen_string_literal: true

module Teek
  # Thin, typed wrapper around Tk's `wm` (window manager) command family -
  # one method per subcommand, coerced to the right Ruby type, reached via
  # {App#wm}.
  #
  # Grouped behind a single accessor instead of more flat App methods, for
  # the same reason {Winfo} is: `wm` is itself one big, well-known Tcl
  # command namespace, so knowing Tcl's `wm title` gets you to {#title}
  # directly. App's own +set_window_title+/+window_geometry+/etc. are kept
  # as thin delegates to this - use whichever reads better to you, they're
  # the same underlying call.
  #
  # Composite behaviors that orchestrate more than a single +wm+ subcommand
  # (App#on_close's callback tracking, for instance) stay top-level App/
  # Widget methods rather than living here - this class is only 1:1 Tcl
  # command wrappers, nothing with Ruby-side state of its own.
  #
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/wm.htm wm
  class Wm
    # @api private
    def initialize(app)
      @app = app
    end

    # @param window [String, Widget] (default: the root window)
    # @return [String] the window's current title
    def title(window: '.')
      @app.tcl_invoke('wm', 'title', window.to_s)
    end

    # @param value [String] new title
    # @param window [String, Widget] (default: the root window)
    # @return [String] the title
    def set_title(value, window: '.')
      @app.tcl_invoke('wm', 'title', window.to_s, value.to_s)
    end

    # @param window [String, Widget] (default: the root window)
    # @return [String] geometry string (e.g. +"400x300+0+0"+)
    def geometry(window: '.')
      @app.tcl_invoke('wm', 'geometry', window.to_s)
    end

    # @param value [String] new geometry (e.g. +"400x300"+, +"400x300+100+50"+)
    # @param window [String, Widget] (default: the root window)
    # @return [String] the geometry
    def set_geometry(value, window: '.')
      @app.tcl_invoke('wm', 'geometry', window.to_s, value.to_s)
    end

    # @param window [String, Widget] (default: the root window)
    # @return [Array(Boolean, Boolean)] [width_resizable, height_resizable]
    def resizable(window: '.')
      parts = @app.tcl_invoke('wm', 'resizable', window.to_s).split
      [@app.tcl_to_bool(parts[0]), @app.tcl_to_bool(parts[1])]
    end

    # @param width [Boolean] allow horizontal resize
    # @param height [Boolean] allow vertical resize
    # @param window [String, Widget] (default: the root window)
    # @return [void]
    def set_resizable(width, height, window: '.')
      @app.tcl_invoke('wm', 'resizable', window.to_s, @app.bool_to_tcl(width), @app.bool_to_tcl(height))
    end

    # Show a window (map it if withdrawn/iconified).
    # @param window [String, Widget] (default: the root window)
    # @return [void]
    def deiconify(window: '.')
      @app.tcl_invoke('wm', 'deiconify', window.to_s)
    end

    # Hide a window without destroying it.
    # @param window [String, Widget] (default: the root window)
    # @return [void]
    def withdraw(window: '.')
      @app.tcl_invoke('wm', 'withdraw', window.to_s)
    end
  end
end
