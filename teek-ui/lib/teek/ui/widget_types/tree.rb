# frozen_string_literal: true

require_relative '../widget_type'

# `tree` and `table` are two DSL names over the same Tk widget
# (ttk::treeview, used with/without -show tree) - see table.rb.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :tree, tk_command: 'ttk::treeview', natively_scrollable: true)
)
