# frozen_string_literal: true

require_relative '../widget_type'

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :canvas, tk_command: 'canvas', leaf: false, natively_scrollable: true)
)
