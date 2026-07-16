# frozen_string_literal: true

module Teek
  module UI
    # What a {Node} gets in its +realized+ slot once the realizer creates a
    # live widget for it: which app owns it, its live Tk path (what a
    # {Handle} acts on - +#configure+, event bindings, +on_close+, ...),
    # and the path its parent's own layout should actually place
    # (+arrange_path+, defaulting to the same as +path+).
    #
    # These two paths only diverge for a node the realizer auto-wraps in a
    # scrollbar (a bare list/text_area/table/tree/canvas, when scrolling
    # applies - see Realizer#create_native_scrollable): +path+ stays the
    # real widget, so a {Handle} keeps acting on it directly, but the
    # widget's actual Tk *parent* is now the wrapper frame the scrollbar
    # lives in - +arrange_path+ points there instead, since that's what
    # has to be packed/gridded into the surrounding layout.
    RealizedNode = Data.define(:app, :path, :arrange_path) do
      # @api private
      def initialize(app:, path:, arrange_path: path)
        super
      end
    end
  end
end
