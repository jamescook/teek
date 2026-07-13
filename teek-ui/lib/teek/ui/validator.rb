# frozen_string_literal: true

require_relative 'errors'

module Teek
  module UI
    # Walks a {Document} before realize and collects ALL problems, so a
    # broken build can be fixed in one pass instead of a cycle of "run, hit
    # the next cryptic Tcl error, fix, repeat." Headless - no interpreter
    # needed, since it only ever inspects the tree.
    #
    # Two severities: problems that are "definitely broken" raise (folded
    # into one {ValidationError} listing every one found); problems that
    # are "probably a mistake" warn via +Kernel#warn+ by default, or raise
    # too under +strict: true+.
    #
    # @note "Mixed pack+grid geometry in one container" (the classic Tk-hangs
    #   hazard) isn't checked here because it's structurally impossible given
    #   how {Realizer} is built: it picks exactly one arrangement strategy
    #   per container, from that container's own node type, so one
    #   container's children can never receive a mix of +pack+ and +grid+
    #   calls. What IS checked instead is the closest real analog: a node
    #   carrying grid-cell position intent whose parent isn't actually a
    #   +:grid+ - only reachable via direct Node/Document manipulation, since
    #   {WidgetDSL#cell} already refuses to run outside a +ui.grid+ block.
    class Validator
      # @param document [Document]
      # @param strict [Boolean] promote warn-level problems (currently just
      #   orphans) to raise-level too
      # @raise [ValidationError]
      def self.validate!(document, strict: false)
        new(document, strict: strict).validate!
      end

      # @api private
      def initialize(document, strict: false)
        @document = document
        @strict = strict
        @errors = []
        @warnings = []
      end

      # @return [void]
      def validate!
        check_stray_cell_intent
        check_grid_cell_collisions
        check_dangling_event_targets
        check_orphans

        @warnings.each { |message| warn "teek-ui: #{message}" }
        raise ValidationError, @errors.join("\n") if @errors.any?
      end

      private

      def check_stray_cell_intent
        each_node_with_parent do |node, parent|
          next unless node.layout && node.layout[:cell]
          next if parent && parent.type == :grid

          @errors << "#{describe(node)} has a grid cell position but its parent (#{describe(parent)}) isn't a " \
                      "ui.grid - its row/col/span would be silently ignored"
        end
      end

      def check_grid_cell_collisions
        each_node_with_parent do |node, _parent|
          next unless node.type == :grid

          node.children
            .group_by { |child| child.layout && child.layout[:cell] && [child.layout[:cell][:row], child.layout[:cell][:col]] }
            .each do |position, children|
              next if position.nil? || children.length <= 1

              row, col = position
              @errors << "#{describe(node)} has more than one widget at row #{row}, col #{col}: " \
                          "#{children.map { |c| describe(c) }.join(', ')}"
            end
        end
      end

      def check_dangling_event_targets
        @document.each_node do |node|
          node.events.each do |binding|
            next unless binding.target
            next if @document.find(binding.target)

            @errors << "#{describe(node)}'s event binding targets :#{binding.target}, but no widget with that name exists"
          end
        end
      end

      def check_orphans
        reachable = {}
        @document.each_node { |node| reachable[node] = true }

        @document.each_named_node do |_name, node|
          next if reachable[node]

          message = "#{describe(node)} is declared but never placed in the layout - it will exist but never realize/show"
          @strict ? @errors << message : @warnings << message
        end
      end

      def each_node_with_parent(node = @document.root, parent = nil, &block)
        block.call(node, parent)
        node.children.each { |child| each_node_with_parent(child, node, &block) }
      end

      def describe(node)
        return 'the document root' unless node
        node.name ? "##{node.type}(:#{node.name})" : "an unnamed ##{node.type}"
      end
    end
  end
end
