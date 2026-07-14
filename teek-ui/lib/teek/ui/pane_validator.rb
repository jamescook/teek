# frozen_string_literal: true

require_relative 'widget_validators'

module Teek
  module UI
    # @api private
    #
    # Registered for the :pane {WidgetValidators} entry below - a pane's own
    # contract: it must be declared directly inside a ui.split. Only
    # reachable via direct Node/Document manipulation, since {WidgetDSL#pane}
    # already refuses to run outside a ui.split block - the same
    # defense-in-depth {TabValidator} does for tabs.
    module PaneValidator
      # @param node [Node] a :pane node - {WidgetValidators} only dispatches
      #   here for that type
      # @param parent [Node, nil]
      # @param document [Document]
      # @param errors [Array<String>] appended to, never raised
      # @return [void]
      def self.call(node, parent, document, errors)
        return if parent && parent.type == :split

        errors << "#{WidgetValidators.describe(node)} is a :pane but its parent " \
                   "(#{WidgetValidators.describe(parent)}) isn't a ui.split"
      end
    end

    WidgetValidators.register(:pane) { |*a| PaneValidator.call(*a) }
  end
end
