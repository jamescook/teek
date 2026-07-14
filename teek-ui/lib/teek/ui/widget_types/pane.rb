# frozen_string_literal: true

require_relative '../widget_type'
require_relative '../pane_validator'

module Teek
  module UI
    # @api private
    #
    # Adds a freshly created :pane's own frame to the enclosing
    # panedwindow, with whatever `#pane` stashed as pane_weight: (if any).
    # `ttk::panedwindow add` is the pane's whole placement - unlike every
    # other container, a pane's frame is never pack/grid-managed on its
    # own (see :pane's own +arranged: false+ below). Registered as :pane's
    # own `post_create:`.
    module PaneRealize
      def self.post_create(app, node, path, parent_path)
        weight = node.opts[:pane_weight]
        opts = weight.nil? ? {} : { weight: weight }
        app.command(parent_path, :add, path, **opts)
      end
    end
  end
end

# :pane has no auto-generated `ui.pane` method - it's only ever reachable
# via the hand-written WidgetDSL#pane, which validates it's declared
# directly inside ui.split. dsl: is a genuine no-op so the registry
# doesn't shadow that with a same-named generic method.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :pane, tk_command: 'ttk::frame', leaf: false, arranged: false,
    post_create: Teek::UI::PaneRealize.method(:post_create),
    validator: Teek::UI::PaneValidator.method(:call),
    dsl: ->(mod) { }
  )
)
