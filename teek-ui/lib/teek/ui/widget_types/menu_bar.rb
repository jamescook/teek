# frozen_string_literal: true

require_relative '../widget_type'

# menu_bar/context_menu are the two entry points into a menu subtree -
# everything under them (nested :menu cascades, :menu_item/:menu_separator/
# :menu_checkbox/:menu_radio entries) is built in one shot by
# Realizer#create_menu_tree, in menu-add order, rather than through the
# generic per-node create/link passes every other node type uses - menu
# entries have no Tk path or geometry-managed arrangement of their own to
# visit separately, so custom_create: hands the whole thing off (see
# create_menu_tree's own doc comment for why it also skips #link entirely).
#
# tk_command: is documentary only here - create_menu_tree calls
# Teek::App#menu directly, never the generic tk_command_for path
# custom_create: bypasses. No auto-generated `ui.menu_bar` method either -
# it's only ever reachable via the hand-written WidgetDSL#menu_bar, which
# validates its parent (see WidgetDSL::MENU_BAR_HOSTS); dsl: is a genuine
# no-op so the registry doesn't shadow that with a same-named generic method.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :menu_bar, tk_command: 'menu', leaf: false, arranged: false,
    custom_create: ->(realizer, node, parent_path) { realizer.send(:create_menu_tree, node, parent_path) },
    dsl: ->(mod) { }
  )
)
