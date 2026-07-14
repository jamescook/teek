# frozen_string_literal: true

require_relative '../widget_type'

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :column, tk_command: 'ttk::frame', leaf: false,
    flow: {
      side: 'top', main_pad: :pady, cross_pad: :padx,
      main_fill: 'y', cross_fill: 'x',
      anchor: { start: 'w', center: 'center', end: 'e' },
    }
  )
)
