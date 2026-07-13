# frozen_string_literal: true

module Teek
  # A single toplevel window, addressed by its Tk path - the window-scoped
  # counterpart to {Widget} (which covers any widget of any type). Groups
  # every `wm` subcommand alongside composite window-lifecycle behaviors
  # (on_close, grab_set/grab_release, modal) that would otherwise keep
  # growing as more and more +window:+-kwarg methods flattened onto {App}
  # - `app.window(path).thing` reads better than threading `window:`
  # through a dozen unrelated top-level methods, and gives callers (like
  # teek-ui's DSL) one coherent object per window instead of loose parts.
  #
  # `App#wm` ({Wm}) and App's own `window_title`/`set_window_title`/etc.
  # convenience methods, plus `App#on_close`/`#grab_set`/`#grab_release`/
  # `#modal`, all delegate here internally - nothing about those public
  # methods changed, this is where their actual work happens now.
  #
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/wm.htm wm
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/grab.htm grab
  class Window
    attr_reader :path

    # @api private
    def initialize(app, path)
      @app = app
      @path = path.to_s
    end

    # @return [String] the Tk window path
    def to_s
      @path
    end

    # -- wm subcommands --

    # @return [String] the window's current title
    def title
      @app.tcl_invoke('wm', 'title', @path)
    end

    # @param value [String] new title
    # @return [String] the title
    def set_title(value)
      @app.tcl_invoke('wm', 'title', @path, value.to_s)
    end

    # @return [String] geometry string (e.g. +"400x300+0+0"+)
    def geometry
      @app.tcl_invoke('wm', 'geometry', @path)
    end

    # @param value [String] new geometry (e.g. +"400x300"+, +"400x300+100+50"+)
    # @return [String] the geometry
    def set_geometry(value)
      @app.tcl_invoke('wm', 'geometry', @path, value.to_s)
    end

    # @return [Array(Boolean, Boolean)] [width_resizable, height_resizable]
    def resizable
      parts = @app.tcl_invoke('wm', 'resizable', @path).split
      [@app.tcl_to_bool(parts[0]), @app.tcl_to_bool(parts[1])]
    end

    # @param width [Boolean] allow horizontal resize
    # @param height [Boolean] allow vertical resize
    # @return [void]
    def set_resizable(width, height)
      @app.tcl_invoke('wm', 'resizable', @path, @app.bool_to_tcl(width), @app.bool_to_tcl(height))
    end

    # Show the window (map it if withdrawn/iconified).
    # @return [void]
    def deiconify
      @app.tcl_invoke('wm', 'deiconify', @path)
    end

    # Hide the window without destroying it.
    # @return [void]
    def withdraw
      @app.tcl_invoke('wm', 'withdraw', @path)
    end

    # -- composite behaviors --

    # Register a handler for the window manager's close button
    # (WM_DELETE_WINDOW - the titlebar close box, Cmd-W, Alt-F4, etc.,
    # depending on platform).
    #
    # Tk's own default behavior (destroy the window) only applies when
    # nothing else has claimed this protocol - setting a handler here
    # replaces it, so the block is entirely responsible for deciding
    # whether the window actually closes. Call {App#destroy} yourself if
    # you want it to; do nothing (or show a confirmation first) if you don't.
    #
    # @example Confirm before quitting
    #   app.window.on_close { app.destroy('.') if app.message_box(message: 'Quit?', type: :yesno) == :yes }
    # @example A toplevel that just hides instead of closing
    #   app.window(settings_window).on_close { app.window(settings_window).withdraw }
    #
    # @yield called when the window's close button is pressed
    # @return [void]
    # @see App#bind
    # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/wm.htm#M46 wm protocol
    def on_close(&block)
      cb = @app.register_callback(block, relay_break_continue: false)
      @app.callback_registry.reconcile([:wm_protocol, @path]) { |before| before.merge('WM_DELETE_WINDOW' => cb) }
      @app.tcl_eval("wm protocol #{@path} WM_DELETE_WINDOW {ruby_callback #{cb}}")
    end

    # Set the input grab on the window - while held, mouse and keyboard
    # events outside it (and its descendants) are redirected to it, the
    # building block {#modal} uses. `grab` is its own Tcl command family,
    # separate from `wm`.
    # @param global [Boolean] a global grab blocks input to every other
    #   application too, not just this one - almost never what you want;
    #   local (the default) is scoped to this application.
    # @return [void]
    # @see #grab_release
    # @see #modal
    def grab_set(global: false)
      args = ['grab', 'set']
      args << '-global' if global
      args << @path
      @app.tcl_invoke(*args)
      nil
    end

    # Release a grab previously set with {#grab_set}. Safe to call even if
    # the window never held the grab - Tk itself treats that as a no-op.
    # @return [void]
    def grab_release
      @app.tcl_invoke('grab', 'release', @path)
      nil
    end

    # Make the window modal: grabs input and sets focus on it immediately.
    # Release it explicitly with {#grab_release} (typically from the
    # window's own dismiss/close handling) when the dialog is done - the
    # grab is NOT released automatically just because this method returns,
    # since a modal dialog is meant to stay grabbed for its whole visible
    # lifetime, not just its setup.
    #
    # Two safety nets guard against a stuck grab locking out the rest of
    # the display: if the window is destroyed while still grabbed (a crash
    # mid-modal, or just forgetting to call {#grab_release} first), a
    # <Destroy> binding releases it; if the optional setup block itself
    # raises, the grab is released immediately rather than left dangling
    # on a half-shown dialog.
    #
    # @example
    #   settings = app.window(settings_path)
    #   settings.modal { settings.deiconify }
    #   # ... later, from the window's own on_close/dismiss handler ...
    #   settings.grab_release
    #
    # @param global [Boolean] see {#grab_set}
    # @yield optional - runs with the grab and focus already set
    # @return [void]
    # @see #grab_set
    # @see #grab_release
    def modal(global: false)
      grab_set(global: global)
      # -force: a modal dialog should own keyboard focus immediately, not
      # merely be first in line whenever the app next happens to get it
      # (plain `focus` only takes effect once the app already has input
      # focus at the OS/WM level).
      @app.tcl_invoke('focus', '-force', @path)
      @app.bind(@path, 'Destroy') { grab_release }
      yield if block_given?
      nil
    rescue
      grab_release
      raise
    end
  end
end
