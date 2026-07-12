# frozen_string_literal: true

module Teek
  # Thin, typed wrapper around Tk's `winfo` command family - one method
  # per subquery, coerced to the right Ruby type, reached via {App#winfo}.
  #
  # Grouped behind a single accessor instead of a dozen-plus flat App
  # methods, since `winfo` is itself one big, well-known Tcl command
  # namespace - knowing Tcl's `winfo width` gets you to {#width} directly.
  # Every method accepts a path String or anything that responds to
  # +to_s+ with one (a {Widget}, for instance).
  #
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/winfo.htm winfo
  class Winfo
    # @api private
    def initialize(app)
      @app = app
    end

    # @param path [String, Widget]
    # @return [Integer] current width in pixels
    def width(path)
      query('width', path).to_i
    end

    # @param path [String, Widget]
    # @return [Integer] current height in pixels
    def height(path)
      query('height', path).to_i
    end

    # @param path [String, Widget]
    # @return [Integer] requested (natural) width in pixels
    def reqwidth(path)
      query('reqwidth', path).to_i
    end

    # @param path [String, Widget]
    # @return [Integer] requested (natural) height in pixels
    def reqheight(path)
      query('reqheight', path).to_i
    end

    # @param path [String, Widget]
    # @return [Integer] x coordinate of the window's top-left corner, in screen pixels
    def rootx(path)
      query('rootx', path).to_i
    end

    # @param path [String, Widget]
    # @return [Integer] y coordinate of the window's top-left corner, in screen pixels
    def rooty(path)
      query('rooty', path).to_i
    end

    # @param path [String, Widget]
    # @return [Integer] x coordinate relative to the parent widget
    def x(path)
      query('x', path).to_i
    end

    # @param path [String, Widget]
    # @return [Integer] y coordinate relative to the parent widget
    def y(path)
      query('y', path).to_i
    end

    # @param path [String, Widget] any window on the same screen (default: the root window)
    # @return [Integer] the mouse pointer's current x coordinate, in screen pixels
    def pointerx(path = '.')
      query('pointerx', path).to_i
    end

    # @param path [String, Widget] any window on the same screen (default: the root window)
    # @return [Integer] the mouse pointer's current y coordinate, in screen pixels
    def pointery(path = '.')
      query('pointery', path).to_i
    end

    # @param path [String, Widget]
    # @return [Boolean] whether a window currently exists at +path+
    def exists?(path)
      query('exists', path) == '1'
    end

    # @param path [String, Widget]
    # @return [String] the Tk widget class (e.g. +"TButton"+, +"Frame"+)
    def class_name(path)
      query('class', path)
    end

    # @param path [String, Widget]
    # @return [Boolean] whether the window is currently mapped (actually displayed)
    def ismapped?(path)
      query('ismapped', path) == '1'
    end

    private

    def query(subcommand, path)
      @app.tcl_invoke('winfo', subcommand, path.to_s)
    end
  end
end
