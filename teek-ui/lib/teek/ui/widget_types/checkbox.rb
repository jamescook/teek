# frozen_string_literal: true

require_relative '../widget_type'

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :checkbox, tk_command: 'ttk::checkbutton', bind_option: :variable)
)
