# frozen_string_literal: true

module Teek
  module UI
    # Build-phase debug tooling: a readable ASCII tree of a {Document}'s
    # current shape, and (opt-in) a step-by-step trace of how it got there.
    # Deliberately its own class, not methods on {Document}/{Node} - those
    # stay focused on constructing/indexing/parent-tracking the retained
    # tree; this is purely an outside observer of it, built the same way an
    # app author's own tooling would be (see {Document#subscribe}).
    class TreeInspector
      # One recorded moment of tree assembly - see {#log}.
      # @!attribute action
      #   @return [Symbol] +:push+/+:pop+ (the build stack, see
      #     {WidgetDSL#current_path}) or +:append+ (a node added via
      #     {Node#add_child})
      # @!attribute node
      #   @return [Node] the node pushed/popped/appended
      # @!attribute path
      #   @return [String] for +:push+/+:pop+, the full ancestry breadcrumb
      #     this node had while on top of the stack; for +:append+, its new
      #     parent's own {Node#display_name}
      Event = Data.define(:action, :node, :path) do
        def to_s
          case action
          when :push then "-> #{path}"
          when :pop then "<- #{path}"
          when :append then "+  #{node.display_name} (under #{path})"
          end
        end
      end

      # @param document [Document]
      # @param trace [Boolean] subscribe to +document+'s own internal
      #   build-event hook immediately, recording every stack push/pop and
      #   node append from this point on - see {#log}. +false+ (the
      #   default) costs nothing beyond this object's own existence:
      #   +document+ never learns whether a TreeInspector is watching or
      #   not, on or off.
      def initialize(document, trace: false)
        @document = document
        @log = []
        subscribe! if trace
      end

      # A readable ASCII tree of the document's CURRENT shape - type,
      # name, and (where present) +opts[:text]+/+opts[:label]+, box-drawn
      # by nesting. Reflects whatever the tree looks like right now; call
      # it again after more building to see the updated shape.
      # @return [String]
      # @example
      #   root
      #   └─ column
      #      ├─ label "Title"
      #      ├─ row
      #      │  ├─ button "OK"
      #      │  └─ button "Cancel"
      #      └─ label "Footer"
      def to_s
        lines = [@document.root.display_name]
        append_tree_lines(@document.root, '', lines)
        lines.join("\n")
      end

      # {#to_s}, straight to stdout.
      # @return [void]
      def print_tree
        puts to_s
      end

      # @return [Array<Event>] every push/pop/append recorded so far, in
      #   order - always empty unless constructed with +trace: true+
      attr_reader :log

      private

      def subscribe!
        @document.subscribe(:push) { |node, path| @log << Event.new(action: :push, node: node, path: path) }
        @document.subscribe(:pop) { |node, path| @log << Event.new(action: :pop, node: node, path: path) }
        @document.subscribe(:append) { |parent, child| @log << Event.new(action: :append, node: child, path: parent.display_name) }
      end

      def append_tree_lines(node, prefix, lines)
        node.children.each_with_index do |child, i|
          last = i == node.children.length - 1
          lines << "#{prefix}#{last ? '└─ ' : '├─ '}#{tree_label(child)}"
          append_tree_lines(child, prefix + (last ? '   ' : '│  '), lines)
        end
      end

      def tree_label(node)
        text = node.opts[:text] || node.opts[:label]
        text ? "#{node.display_name} #{text.to_s.inspect}" : node.display_name
      end
    end
  end
end
