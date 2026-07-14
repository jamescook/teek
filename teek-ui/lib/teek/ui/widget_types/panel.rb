# frozen_string_literal: true

require_relative '../widget_type'

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :panel, tk_command: 'ttk::frame', leaf: false)
)
