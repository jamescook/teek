# frozen_string_literal: true

module Teek
  # Thin, typed wrapper around Tk's `clipboard` command family, reached
  # via {App#clipboard}.
  #
  # Doesn't touch text widgets' own copy/cut/paste at all - `ttk::entry`/
  # `text` already bind `<<Copy>>`/`<<Cut>>`/`<<Paste>>` to the expected
  # platform keys (Control-c/x/v, plus their Command-key equivalents on
  # macOS) via Tk's own built-in class bindings, with nothing for teek to
  # wire up. This class is purely for reading/writing the clipboard
  # directly from app code (e.g. a "Copy to Clipboard" button that isn't
  # itself a text widget's own selection).
  #
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/clipboard.htm clipboard
  class Clipboard
    # @api private
    def initialize(app)
      @app = app
    end

    # Replace the clipboard's contents outright - Tk's own `clipboard
    # clear` followed by `clipboard append` two-step, done as one call.
    # @param text [String]
    # @return [void]
    def set(text)
      @app.tcl_invoke('clipboard', 'clear')
      @app.tcl_invoke('clipboard', 'append', '--', text.to_s)
      nil
    end

    # @return [String, nil] the clipboard's current text, or +nil+ if
    #   it's empty/has no owner (Tk raises a TclError for this rather
    #   than returning an empty string)
    def get
      @app.tcl_invoke('clipboard', 'get')
    rescue Teek::TclError
      nil
    end

    # Clear the clipboard without setting new contents.
    # @return [void]
    def clear
      @app.tcl_invoke('clipboard', 'clear')
      nil
    end
  end
end
