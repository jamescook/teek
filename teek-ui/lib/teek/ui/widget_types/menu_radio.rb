# frozen_string_literal: true

require_relative '../widget_type'
require_relative '../menu_entry_addressing'

# See widget_types/menu_item.rb for the shared reasoning - :menu_radio is
# a menu entry kind, addressed the same way (MenuEntryAddressing),
# reachable only via the hand-written MenuBuilder#radio.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :menu_radio, tk_command: 'menu', addressing: Teek::UI::MenuEntryAddressing,
    dsl: ->(mod) { }
  )
)
