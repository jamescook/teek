# frozen_string_literal: true

require_relative 'node'
require_relative 'scope'

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

      # Construct a node and register it under its name (if any), scoped
      # to +scope+ - the same name used in two different scopes indexes
      # as two distinct entries, so a component's local +:save+ never
      # collides with another component's (or the top level's) own
      # +:save+. Does NOT attach it to any parent - the caller does that
      # with {Node#add_child}, so Document never needs to know about a
      # current-parent stack.
      #
      # The node's own +name+/+key+ stay bare/unqualified - only this
      # index is scope-aware. A node's real Tk path is already distinct
      # per scope with no help needed here, since it's built from the
      # parent chain ({Realizer#allocate_path}), and two components'
      # subtrees are never siblings of themselves.
      # @param type [Symbol]
      # @param name [Symbol, nil]
      # @param opts [Hash]
      # @param scope [Scope] see {Scope} - defaults to {Scope::TOP_LEVEL}
      # @return [Node]
      # @raise [ArgumentError] if +name+ is already registered within +scope+
      def create(type:, name: nil, opts: {}, scope: Scope::TOP_LEVEL)
        node = Node.new(type: type, name: name, key: generate_key(name), opts: opts, scope: scope)
        register(scope, node) if name
        node
      end

      # @param name [Symbol]
      # @param scope [Scope] must be the same {Scope} instance the node
      #   was {#create}d with - a name registered inside a scope is never
      #   found by a lookup in a different one, or vice versa
      # @return [Node, nil]
      def find(name, scope: Scope::TOP_LEVEL)
        @index[[scope, name]]
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

      def register(scope, node)
        key = [scope, node.name]
        if @index.key?(key)
          suffix = scope.top_level? ? '' : ' in the same component'
          raise ArgumentError, "duplicate widget name :#{node.name} - already used by a #{@index[key].type} node#{suffix}"
        end

        @index[key] = node
      end

      def generate_key(name)
        return name.to_s if name

        @next_auto_key += 1
        "#anon#{@next_auto_key}"
      end
    end
  end
end
