# frozen_string_literal: true

require_relative '../widget_type'

# :split has no auto-generated `ui.split` method - it's only ever reachable
# via the hand-written WidgetDSL#split, which validates orientation: and
# translates it to the real -orient option before creating the node.
# dsl: is a genuine no-op so the registry doesn't shadow that with a
# same-named generic method. `orient:` itself is a real ttk::panedwindow
# option, so it needs no reserved-option handling here - it passes through
# the generic widget-creation call untouched.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :split, tk_command: 'ttk::panedwindow', leaf: false,
    dsl: ->(mod) { }
  )
)
