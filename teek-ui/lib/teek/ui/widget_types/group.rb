# frozen_string_literal: true

require_relative '../widget_type'

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :group, tk_command: 'ttk::labelframe', leaf: false)
)
