# frozen_string_literal: true

require_relative '../widget_type'

# There's no Tk protocol to hook a scrollbar into arbitrary widgets (unlike
# a natively-scrollable widget's own wrapping - see list.rb/table.rb/etc),
# so :scrollable's children are created inside an embedded canvas+viewport
# it builds itself (Realizer#create_scrollable) rather than directly under
# its own path - custom_children: takes over from the generic
# "create every child normally" step once its own frame already exists.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :scrollable, tk_command: 'ttk::frame', leaf: false,
    custom_children: ->(realizer, node, path) { realizer.send(:create_scrollable, node, path) },
    arrange: ->(realizer, node, children) { realizer.send(:arrange_scrollable_frame, node, children) }
  )
)
