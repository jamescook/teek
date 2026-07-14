# frozen_string_literal: true

require_relative '../widget_type'

# A canvas is as often fixed drawing as scrollable content, unlike the
# other natively-scrollable types - scroll_default: points its own
# auto-scrollable wrapping at Teek::UI.auto_scroll_canvas (false by
# default) instead of the shared Teek::UI.auto_scroll (true by default)
# every other natively-scrollable type falls back to.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :canvas, tk_command: 'canvas', leaf: false,
    natively_scrollable: true, scroll_default: :auto_scroll_canvas
  )
)
