# frozen_string_literal: true

require_relative '../widget_type'

# A plain leaf with no bind option, no scrolling, and no realize setup
# beyond the generic widget-creation command - every field but
# type/tk_command is a leaf default.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :divider, tk_command: 'ttk::separator')
)
