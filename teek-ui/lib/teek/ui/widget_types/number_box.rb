# frozen_string_literal: true

require_relative '../widget_type'

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :number_box, tk_command: 'ttk::spinbox', bind_option: :textvariable)
)
