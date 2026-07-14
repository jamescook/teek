# frozen_string_literal: true

require_relative '../widget_type'

# See widget_types/menu_bar.rb for the shared reasoning - context_menu is
# the other entry point into the same Realizer#create_menu_tree traversal,
# just never attached to a -menu option automatically (popped up via
# Handle#on_right_click instead).
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :context_menu, tk_command: 'menu', leaf: false, arranged: false,
    custom_create: ->(realizer, node, parent_path) { realizer.send(:create_menu_tree, node, parent_path) },
    dsl: ->(mod) { }
  )
)
