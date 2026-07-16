# frozen_string_literal: true

require_relative '../widget_type'
require_relative '../grid_validator'

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :grid, tk_command: 'ttk::frame', leaf: false,
    arrange: ->(realizer, node, children) { realizer.send(:arrange_grid, node, children) },
    validator: Teek::UI::GridValidator.method(:call)
  )
)
