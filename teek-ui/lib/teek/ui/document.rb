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
        @root = Node.new(type: :root, document: self)
        @index = {}
        @next_auto_key = 0
        @used_segments = {}
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
        node = Node.new(type: type, name: name, key: generate_key(name), opts: opts, scope: scope, document: self)
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

      # @api private - called by {Realizer#allocate_path}, which gets a
      # fresh instance for every separate realize pass (the initial
      # realize, each {Session#add}, each lazily-{Handle#realize!}d
      # screen) - tracking claims here instead keeps them honest across
      # every one of those passes for this Document's whole lifetime.
      # Two mounts of the same component requesting the same key under
      # the same real parent (e.g. a reusable row/screen, realized more
      # than once - see {WidgetDSL#component}) get distinct, disambiguated
      # segments; the common, non-colliding case keeps its plain segment
      # unchanged.
      # @param parent_path [String]
      # @param segment [String] the requested (not yet disambiguated) segment
      # @return [String] +segment+, or +segment+ suffixed to make it unique
      #   under +parent_path+ if this is a repeat
      def claim_path_segment(parent_path, segment)
        seen = (@used_segments[parent_path] ||= Hash.new(0))
        count = seen[segment]
        seen[segment] += 1
        count.zero? ? segment : "#{segment}##{count + 1}"
      end

      # Removes +node+ from the name index, scoped exactly like
      # {#register} does - a no-op if +node+ was never named (nothing to
      # remove) or already unregistered. Called by {Handle#destroy!} for
      # a destroyed node and every named descendant of its own subtree
      # (Tk destroys descendants recursively, so their names need to
      # stop resolving too), so a later widget can reuse the same name
      # in the same scope, and {#find} correctly reports the name as
      # gone in the meantime.
      # @param node [Node]
      # @return [void]
      def unregister(node)
        return unless node.name

        @index.delete([node.scope, node.name])
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
