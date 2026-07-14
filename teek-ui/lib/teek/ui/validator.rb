# frozen_string_literal: true

require_relative 'errors'
require_relative 'widget_validators'
require_relative 'grid_validator'
require_relative 'tab_validator'
require_relative 'pane_validator'

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
    # This class runs the checks that span the whole tree or relate
    # arbitrary nodes to each other (dangling event targets, orphans). A
    # specific widget/container's own contract (a grid's children all need
    # cells, a tab's parent must be a ui.tabs, ...) lives in its own
    # {WidgetValidators}-registered validator instead (see
    # {GridValidator}/{TabValidator}/{PaneValidator}), dispatched by node
    # type the same way {Teek::CommandInterceptors} dispatches by widget
    # type. One depth-first walk covers both the document-level checks
    # below and every registered widget validator.
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
    #   checks in {GridValidator}/{TabValidator}/{PaneValidator} actually
    #   guard against). If it happens, Tk itself is a synchronous backstop:
    #   it refuses a second geometry manager on an already-managed master
    #   with an immediate, clear +Teek::TclError+ ("cannot use geometry
    #   manager X inside Y") rather than the classic silent hang - but the
    #   DSL has no way to stop the mistake up front, so avoid mixing raw
    #   geometry calls onto a DSL-managed master (see the README's escape
    #   hatch section).
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
        @reachable = {}
      end

      # @return [void]
      def validate!
        walk(@document.root, nil)
        check_orphans

        @warnings.each { |message| warn "teek-ui: #{message}" }
        raise ValidationError, @errors.join("\n") if @errors.any?
      end

      private

      # The single tree traversal every check below rides along on - marks
      # each node reachable (for {#check_orphans}), dispatches to every
      # {WidgetValidators}-registered validator for the node's own type,
      # and runs {GridValidator#check_stray_cell} (see its own comment for
      # why that one can't be type-dispatched) plus the dangling-event-
      # target check, both of which genuinely span arbitrary node types.
      def walk(node, parent)
        @reachable[node] = true

        GridValidator.check_stray_cell(node, parent, @errors)
        WidgetValidators.for_type(node.type).each { |validator| validator.call(node, parent, @document, @errors) }
        check_dangling_event_targets(node)

        node.children.each { |child| walk(child, node) }
      end

      def check_dangling_event_targets(node)
        node.events.each do |binding|
          next unless binding.target
          next if @document.find(binding.target)

          @errors << "#{WidgetValidators.describe(node)}'s event binding targets :#{binding.target}, " \
                      "but no widget with that name exists"
        end
      end

      def check_orphans
        @document.each_named_node do |_name, node|
          next if @reachable[node]

          message = "#{WidgetValidators.describe(node)} is declared but never placed in the layout - " \
                     "it will exist but never realize/show"
          @strict ? @errors << message : @warnings << message
        end
      end
    end
  end
end
