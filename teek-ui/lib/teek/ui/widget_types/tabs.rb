# frozen_string_literal: true

require_relative '../widget_type'

# A plain container holding #tab-declared pages - each one placed entirely
# by `ttk::notebook add` (see tab.rb's own arranged: false), so :tabs
# itself never has any arrangeable children and needs no custom arrange:.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :tabs, tk_command: 'ttk::notebook', leaf: false)
)
