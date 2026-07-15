# frozen_string_literal: true

require_relative 'scope'

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
      attr_reader :type, :name, :opts, :children, :events, :parent, :scope
      attr_accessor :key, :layout, :realized

      # @param type [Symbol] node kind, e.g. +:button+, +:column+, +:var+
      # @param name [Symbol, nil] explicit stable name, for addressing (+ui[:name]+)
      # @param key [String, nil] stable identity; defaults to +name+'s string form
      # @param opts [Hash] widget/node options as plain Ruby values
      # @param scope [Scope] the component scope this node was built in -
      #   {Scope::TOP_LEVEL} (the default) for a build that never calls
      #   {WidgetDSL#component}
      def initialize(type:, name: nil, key: nil, opts: {}, scope: Scope::TOP_LEVEL)
        @type = type
        @name = name
        @key = key || name&.to_s
        @opts = opts
        @children = []
        @layout = nil
        @events = []
        @realized = nil
        @parent = nil
        @scope = scope
      end

      # @param node [Node]
      # @return [Node] the node just added
      def add_child(node)
        @children << node
        node.parent = self
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

      # This node's address, computed purely from the retained tree
      # (name/key + {#parent}) - no Tk involved, correct before realize.
      # For an ordinary widget this already equals the real Tk path
      # ({Realizer#allocate_path} walks this identical parent/segment
      # structure); for anything without an independent Tk path of its
      # own (a menu entry, say), an {Addressing} strategy extends past
      # this with its own marker rather than pretending it's a real one.
      # The other documented exception: a reusable component mounted more
      # than once under the same real parent - {Realizer#allocate_path}
      # only discovers that repeat (and disambiguates the later mounts'
      # paths) at realize, so this can't predict it ahead of time either.
      # A node that isn't attached anywhere yet (+parent+ nil, and not
      # itself the root) is treated as top-level - the best answer
      # available without a tree to place it in.
      # @return [String] e.g. +"."+, +".toolbar"+, +".toolbar.save"+
      def logical_path
        return '.' if type == :root

        prefix = (parent.nil? || parent.type == :root) ? '.' : "#{parent.logical_path}."
        "#{prefix}#{name || key}"
      end

      protected

      attr_writer :parent
    end
  end
end
