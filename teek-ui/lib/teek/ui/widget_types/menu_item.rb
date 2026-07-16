# frozen_string_literal: true

require_relative '../widget_type'
require_relative '../menu_entry_addressing'

# :menu_item never flows through the generic Realizer#create path -
# Realizer#create_menu_tree issues its own `menu add command` call for
# every :menu_item child directly, so leaf:/arranged:/etc are inert here.
# Registered so its addressing: (how a named item's Handle reads/writes
# its live -state/-label/...) is discoverable from the registry, the same
# way every other type's is - see menu_entry_addressing.rb. No
# auto-generated `ui.menu_item` method either - it's only ever reachable
# via the hand-written MenuBuilder#item; dsl: is a genuine no-op so the
# registry doesn't shadow that with a same-named generic method.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :menu_item, tk_command: 'menu', addressing: Teek::UI::MenuEntryAddressing,
    dsl: ->(mod) { }
  )
)
