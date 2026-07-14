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
    #   hazard) isn't checked here because, within the pure DSL layout path,
    #   it can't happen: {Realizer#arrange_children} picks exactly one
    #   arrangement strategy per container, from that container's own node
    #   type, and every container realizes into its own dedicated Tk master
    #   - a guarantee locked down by a realizer test (test_realizer.rb)
    #   asserting no master ever receives calls from more than one manager,
    #   so a future refactor that shares/flattens frames fails a test
    #   instead of shipping the hazard silently.
    #
    #   That guarantee only covers what the DSL itself can construct,
    #   though - it says nothing about the escape hatch. +ui.raw+,
    #   +session.app.command+, and a live handle's own +app.command+ calls
    #   are opaque Procs the tree-walking validator can't see inside, so a
    #   raw +pack+/+grid+ call from one of those can still target a master
    #   the DSL already manages - that's the one real, unguardable vector,
    #   not "direct Node/Document manipulation" (which is what the narrower
    #   check below actually guards against). If it happens, Tk itself is a
    #   synchronous backstop: it refuses a second geometry manager on an
    #   already-managed master with an immediate, clear +Teek::TclError+
    #   ("cannot use geometry manager X inside Y") rather than the classic
    #   silent hang - but the DSL has no way to stop the mistake up front,
    #   so avoid mixing raw geometry calls onto a DSL-managed master (see
    #   the README's escape hatch section).
    #
    #   What IS checked here is the closest real analog reachable through
    #   the tree: a node carrying grid-cell position intent whose parent
    #   isn't actually a +:grid+ - only reachable via direct Node/Document
    #   manipulation, since {WidgetDSL#cell} already refuses to run outside
    #   a +ui.grid+ block.
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
        check_stray_tab_intent
        check_stray_pane_intent
        check_grid_cell_collisions
        check_grid_children_missing_a_cell
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

      # The opposite direction from {#check_stray_cell_intent}: a direct
      # child of a +:grid+ that was never placed with +g.cell(row:, col:)+.
      # {Realizer#arrange_grid} still raises on this too (kept as a
      # belt-and-suspenders backstop for the one path that skips
      # validation entirely - {Session#add}'s incremental realize), but
      # this is now the primary detection, so the mistake surfaces
      # pre-realize, collected alongside every other problem, instead of
      # crashing mid-realize.
      NOT_GRID_ARRANGED_TYPES = %i[raw_op window menu_bar context_menu tab].freeze

      def check_grid_children_missing_a_cell
        each_node_with_parent do |node, parent|
          next unless parent && parent.type == :grid
          next if NOT_GRID_ARRANGED_TYPES.include?(node.type)
          next if node.layout && node.layout[:cell]

          @errors << "#{describe(node)} is a direct child of a grid but was never placed with " \
                      "g.cell(row:, col:) { ... }"
        end
      end

      # Only reachable via direct Node/Document manipulation, since
      # {WidgetDSL#tab} already refuses to run outside a +ui.tabs+ block -
      # the same defense-in-depth {#check_stray_cell_intent} does for grid.
      def check_stray_tab_intent
        each_node_with_parent do |node, parent|
          next unless node.type == :tab
          next if parent && parent.type == :tabs

          @errors << "#{describe(node)} is a :tab but its parent (#{describe(parent)}) isn't a ui.tabs"
        end
      end

      # Only reachable via direct Node/Document manipulation, since
      # {WidgetDSL#pane} already refuses to run outside a +ui.split+ block -
      # the same defense-in-depth {#check_stray_tab_intent} does for tabs.
      def check_stray_pane_intent
        each_node_with_parent do |node, parent|
          next unless node.type == :pane
          next if parent && parent.type == :split

          @errors << "#{describe(node)} is a :pane but its parent (#{describe(parent)}) isn't a ui.split"
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
