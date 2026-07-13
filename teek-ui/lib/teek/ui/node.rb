# frozen_string_literal: true

module Teek
  module UI
    # A single element of the retained-mode tree - a widget, layout
    # container, reactive var, or deferred build-time op (the categories
    # from the architecture doc; this class itself is generic across all of
    # them). Plain Ruby, no Tk: constructible, mutable, and traversable with
    # no interpreter, which is what makes the tree headless-testable.
    #
    # +key+ is this node's stable identity - the explicit +name+ if given,
    # else whatever the owning {Document} assigns. +realized+ stays nil for
    # the whole build phase; a realizer fills it in later with a live
    # handle.
    class Node
      attr_reader :type, :name, :opts, :children, :events
      attr_accessor :key, :layout, :realized

      # @param type [Symbol] node kind, e.g. +:button+, +:column+, +:var+
      # @param name [Symbol, nil] explicit stable name, for addressing (+ui[:name]+)
      # @param key [String, nil] stable identity; defaults to +name+'s string form
      # @param opts [Hash] widget/node options as plain Ruby values
      def initialize(type:, name: nil, key: nil, opts: {})
        @type = type
        @name = name
        @key = key || name&.to_s
        @opts = opts
        @children = []
        @layout = nil
        @events = []
        @realized = nil
      end

      # @param node [Node]
      # @return [Node] the node just added
      def add_child(node)
        @children << node
        node
      end

      # Depth-first, pre-order traversal of this node and its descendants.
      # @yieldparam node [Node]
      # @return [Enumerator] if no block given
      def each(&block)
        return enum_for(:each) unless block

        block.call(self)
        children.each { |child| child.each(&block) }
      end
    end
  end
end
