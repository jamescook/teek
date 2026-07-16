# frozen_string_literal: true

require_relative '../widget_type'

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :dropdown, tk_command: 'ttk::combobox', bind_option: :textvariable)
)
