# frozen_string_literal: true

require_relative 'node'

module Teek
  module UI
    # The build-phase tree: an unattached root {Node} plus a name index
    # (Symbol -> Node). Plain Ruby, no Tk - building and traversing a
    # Document never touches an interpreter, which is what makes the DSL
    # headless-testable.
    #
    # Document only constructs and indexes nodes; it has no opinion on tree
    # shape (which node is whose parent) - the build surface decides that by
    # calling {Node#add_child} itself, so Document stays reusable underneath
    # whatever parent-tracking scheme the builder uses.
    class Document
      # @return [Node] the tree's root - starts with no children
      attr_reader :root

      def initialize
        @root = Node.new(type: :root)
        @index = {}
        @next_auto_key = 0
      end

      # Construct a node and register it under its name (if any). Does NOT
      # attach it to any parent - the caller does that with
      # {Node#add_child}, so Document never needs to know about a
      # current-parent stack.
      # @param type [Symbol]
      # @param name [Symbol, nil]
      # @param opts [Hash]
      # @return [Node]
      # @raise [ArgumentError] if +name+ is already registered
      def create(type:, name: nil, opts: {})
        node = Node.new(type: type, name: name, key: generate_key(name), opts: opts)
        register(node) if name
        node
      end

      # @param name [Symbol]
      # @return [Node, nil]
      def find(name)
        @index[name]
      end
      alias_method :[], :find

      # Depth-first, pre-order traversal of the whole tree from {#root}.
      # @yieldparam node [Node]
      # @return [Enumerator] if no block given
      def each_node(&block)
        root.each(&block)
      end

      # Every named node, regardless of whether it's actually attached
      # anywhere in the tree - see {Validator}'s orphan check, which is
      # exactly the reason this differs from {#each_node}.
      # @yieldparam name [Symbol]
      # @yieldparam node [Node]
      # @return [Enumerator] if no block given
      def each_named_node(&block)
        return enum_for(:each_named_node) unless block

        @index.each(&block)
      end

      private

      def register(node)
        if @index.key?(node.name)
          raise ArgumentError, "duplicate widget name :#{node.name} - already used by a #{@index[node.name].type} node"
        end

        @index[node.name] = node
      end

      def generate_key(name)
        return name.to_s if name

        @next_auto_key += 1
        "#anon#{@next_auto_key}"
      end
    end
  end
end
