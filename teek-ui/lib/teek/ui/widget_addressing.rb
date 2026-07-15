# frozen_string_literal: true

require_relative 'errors'
require_relative 'option_dump_parsing'

module Teek
  module UI
    # @api private
    #
    # The default {WidgetType#addressing} strategy - an ordinary Tk
    # widget with an independent path of its own, driving +#path+/
    # +#configure+ through it directly. See {WidgetType#addressing} for
    # how a type opts into a different strategy (e.g. {MenuEntryAddressing}).
    class WidgetAddressing
      # @api private
      def initialize(node)
        @node = node
      end

      # @return [String] the real Tk widget path
      # @raise [NotRealizedError] before realize
      def virtual_path
        realized.path
      end

      # @param opts [Hash]
      # @return [void]
      # @raise [NotRealizedError] before realize
      def configure(**opts)
        realized.app.command(realized.path, :configure, **opts)
      end

      # @return [Hash{Symbol => String}] every current option/value Tk
      #   reports for this widget right now
      # @raise [NotRealizedError] before realize
      def option_dump
        OptionDumpParsing.parse(realized.app, realized.app.command(realized.path, :configure))
      end

      private

      def realized
        @node.realized or raise NotRealizedError
      end
    end
  end
end
