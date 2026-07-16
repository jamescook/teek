# frozen_string_literal: true

require_relative '../widget_type'

# `table` and `tree` are two DSL names over the same Tk widget
# (ttk::treeview, used with/without -show tree) - see tree.rb.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :table, tk_command: 'ttk::treeview', natively_scrollable: true)
)
