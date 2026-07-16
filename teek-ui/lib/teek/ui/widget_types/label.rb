# frozen_string_literal: true

require_relative '../widget_type'

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :label, tk_command: 'ttk::label', bind_option: :textvariable)
)
