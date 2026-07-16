# frozen_string_literal: true

require_relative '../widget_type'
require_relative '../tab_validator'

module Teek
  module UI
    # @api private
    #
    # Adds a freshly created :tab's own frame to the enclosing notebook as
    # a page, labeled with whatever `#tab` stashed as tab_label:.
    # `ttk::notebook add` is the page's whole placement - unlike every
    # other container, a tab's frame is never pack/grid-managed on its own
    # (see :tab's own +arranged: false+ below). Registered as :tab's own
    # `post_create:`.
    module TabRealize
      def self.post_create(app, node, path, parent_path)
        app.command(parent_path, :add, path, text: node.opts[:tab_label])
      end
    end
  end
end

# :tab has no auto-generated `ui.tab` method - it's only ever reachable via
# the hand-written WidgetDSL#tab, which validates it's declared directly
# inside ui.tabs. dsl: is a genuine no-op so the registry doesn't shadow
# that with a same-named generic method.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :tab, tk_command: 'ttk::frame', leaf: false, arranged: false,
    post_create: Teek::UI::TabRealize.method(:post_create),
    validator: Teek::UI::TabValidator.method(:call),
    dsl: ->(mod) { }
  )
)
