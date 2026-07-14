# frozen_string_literal: true

require_relative '../widget_type'

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :row, tk_command: 'ttk::frame', leaf: false,
    flow: {
      side: 'left', main_pad: :padx, cross_pad: :pady,
      main_fill: 'x', cross_fill: 'y',
      anchor: { start: 'n', center: 'center', end: 's' },
    }
  )
)
