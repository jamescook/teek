# frozen_string_literal: true

require_relative 'widget_validators'

module Teek
  module UI
    # @api private
    #
    # Registered for the :tab {WidgetValidators} entry below - a tab's own
    # contract: it must be declared directly inside a ui.tabs. Only
    # reachable via direct Node/Document manipulation, since {WidgetDSL#tab}
    # already refuses to run outside a ui.tabs block - the same
    # defense-in-depth {GridValidator#check_stray_cell} does for grid.
    module TabValidator
      # @param node [Node] a :tab node - {WidgetValidators} only dispatches
      #   here for that type
      # @param parent [Node, nil]
      # @param document [Document]
      # @param errors [Array<String>] appended to, never raised
      # @return [void]
      def self.call(node, parent, document, errors)
        return if parent && parent.type == :tabs

        errors << "#{WidgetValidators.describe(node)} is a :tab but its parent " \
                   "(#{WidgetValidators.describe(parent)}) isn't a ui.tabs"
      end
    end

    WidgetValidators.register(:tab) { |*a| TabValidator.call(*a) }
  end
end
