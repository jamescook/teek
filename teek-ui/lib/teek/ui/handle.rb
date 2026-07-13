# frozen_string_literal: true

require_relative 'errors'
require_relative 'realized_node'

module Teek
  module UI
    # The single handle type for a node, valid across both phases (Resolved
    # decision #3 in the architecture doc - no separate build-time NodeRef).
    # During build you compose/name it; live methods (#path, #configure) raise
    # {NotRealizedError} until the node's +realized+ slot is filled in by the
    # realizer, then the same Handle object drives the real widget through it.
    class Handle
      # @api private
      def initialize(node)
        @node = node
      end

      # @return [Symbol] the node's type, e.g. +:button+
      def type
        @node.type
      end

      # @return [Symbol, nil] the node's explicit name
      def name
        @node.name
      end

      # @return [String] the live Tk widget path
      # @raise [NotRealizedError] before realize
      def path
        realized.path
      end

      # Mutate the live widget's options.
      # @param opts [Hash] widget options, e.g. +text: "Go"+
      # @raise [NotRealizedError] before realize
      def configure(**opts)
        realized.app.command(realized.path, :configure, **opts)
      end

      private

      def realized
        @node.realized or raise NotRealizedError
      end
    end
  end
end
