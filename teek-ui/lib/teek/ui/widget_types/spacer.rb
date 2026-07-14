# frozen_string_literal: true

require_relative '../widget_type'

# A flexible gap - the named replacement for the "invisible spring row"
# trick (an empty row/column given all the leftover weight). A leaf with
# `grow: true` baked in and no arguments at all, so it needs its own `dsl:`
# rather than the generic leaf default (`name = nil, **opts`).
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :spacer, tk_command: 'ttk::frame',
    dsl: ->(mod) { mod.send(:define_method, :spacer) { append_leaf(:spacer, nil, grow: true) } }
  )
)
