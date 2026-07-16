# frozen_string_literal: true

require_relative '../widget_type'

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :progress, tk_command: 'ttk::progressbar', bind_option: :variable)
)
