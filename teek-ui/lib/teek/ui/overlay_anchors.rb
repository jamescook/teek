# frozen_string_literal: true

module Teek
  module UI
    # @api private
    #
    # ui.overlay's at: vocabulary - corners, center, and the four edge
    # midpoints, spelled in plain English rather than Tk's own compass
    # anchors (nw/n/ne/w/center/e/sw/s/se) - the same litmus test every
    # other DSL name follows (decoding one should never need Tk
    # knowledge). Each maps to `place`'s own -relx/-rely/-anchor, needed
    # both to validate at: ({WidgetDSL#overlay}) and to actually place the
    # widget ({Realizer#place_overlay}) - one shared table so the two can
    # never drift out of sync with each other.
    module OverlayAnchors
      POSITIONS = {
        top_left: { relx: 0.0, rely: 0.0, anchor: 'nw' },
        top: { relx: 0.5, rely: 0.0, anchor: 'n' },
        top_right: { relx: 1.0, rely: 0.0, anchor: 'ne' },
        left: { relx: 0.0, rely: 0.5, anchor: 'w' },
        center: { relx: 0.5, rely: 0.5, anchor: 'center' },
        right: { relx: 1.0, rely: 0.5, anchor: 'e' },
        bottom_left: { relx: 0.0, rely: 1.0, anchor: 'sw' },
        bottom: { relx: 0.5, rely: 1.0, anchor: 's' },
        bottom_right: { relx: 1.0, rely: 1.0, anchor: 'se' },
      }.freeze
    end
  end
end
