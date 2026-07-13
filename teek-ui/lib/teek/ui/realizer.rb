# frozen_string_literal: true

require_relative 'realized_node'

module Teek
  module UI
    # Walks a {Document} and realizes it into a live {Teek::App} - two
    # passes (Resolved decision #4 in the architecture doc):
    #
    # 1. +create+ - creates every widget, allocates a hierarchical/meaningful
    #    Tk path per node, fills each node's +realized+ slot.
    # 2. +link+ - applies (placeholder, see below) geometry and wires event
    #    bindings, resolving +target:+ references by name. Runs after
    #    +create+ has finished the WHOLE tree, so a target declared later in
    #    the build already has a live path by the time it's looked up - that
    #    ordering is what makes forward references work.
    #
    # Every widget creation and mutation goes through {Teek::App#command}, so
    # teek's interceptor/leak-cleanup layer applies automatically.
    #
    # @note Layout is real for +:column+/+:row+ (flow packing driven by
    #   +gap:+/+align:+/+pad:+ and each child's +grow:+), but still a
    #   placeholder for every other container type - their children just
    #   pack top-to-bottom with no options. There's no grid/overlay layout
    #   yet either.
    class Realizer
      # DSL node type -> Tk widget-creation command.
      TK_COMMANDS = {
        text_box: 'ttk::entry',
        text_area: 'text',
        label: 'ttk::label',
        button: 'ttk::button',
        checkbox: 'ttk::checkbutton',
        radio: 'ttk::radiobutton',
        slider: 'ttk::scale',
        dropdown: 'ttk::combobox',
        number_box: 'ttk::spinbox',
        list: 'listbox',
        table: 'ttk::treeview',
        tree: 'ttk::treeview',
        progress: 'ttk::progressbar',
        divider: 'ttk::separator',
        panel: 'ttk::frame',
        group: 'ttk::labelframe',
        canvas: 'canvas',
        window: 'toplevel',
        column: 'ttk::frame',
        row: 'ttk::frame',
        spacer: 'ttk::frame',
      }.freeze

      # gap:/align:/pad: are layout-DSL keywords, not real Tk options - never
      # passed through to a widget-creation call, on any node type (no Tk
      # widget has options actually named -gap/-align/-pad).
      LAYOUT_ONLY_OPTIONS = %i[gap align pad].freeze

      # :column/:row flow-packing config, mirrored across the main axis
      # (stack direction) and cross axis (perpendicular to it).
      FLOW = {
        column: {
          side: 'top', main_pad: :pady, cross_pad: :padx,
          main_fill: 'y', cross_fill: 'x',
          anchor: { start: 'w', center: 'center', end: 'e' },
        },
        row: {
          side: 'left', main_pad: :padx, cross_pad: :pady,
          main_fill: 'x', cross_fill: 'y',
          anchor: { start: 'n', center: 'center', end: 's' },
        },
      }.freeze

      # @param app [Teek::App]
      # @param document [Document]
      # @return [void]
      def self.realize(app, document)
        new(app, document).realize
      end

      # @api private
      def initialize(app, document)
        @app = app
        @document = document
        @auto_segment_count = 0
      end

      # @return [void]
      def realize
        create(@document.root, '.')
        link(@document.root)
      end

      private

      def create(node, parent_path)
        path =
          if node.type == :root
            parent_path
          else
            allocate_path(node, parent_path)
          end

        unless node.type == :root
          tk_command = TK_COMMANDS.fetch(node.type) {
            raise ArgumentError, "no Tk command mapped for node type :#{node.type}"
          }
          @app.command(tk_command, path, **node.opts.except(*LAYOUT_ONLY_OPTIONS))
          node.realized = RealizedNode.new(app: @app, path: path)
        end

        node.children.each { |child| create(child, path) }
      end

      def link(node)
        pack_children(node)
        node.events.each { |binding| wire_event(node, binding) }
        node.children.each { |child| link(child) }
      end

      def pack_children(node)
        flow = FLOW[node.type]
        return node.children.each { |child| @app.command(:pack, child.realized.path) } unless flow

        gap = node.opts.fetch(:gap, 0)
        align = node.opts.fetch(:align, :start)
        pad = node.opts.fetch(:pad, 0)
        last_index = node.children.length - 1

        node.children.each_with_index do |child, index|
          opts = flow_pack_opts(
            flow: flow, child: child, index: index, last_index: last_index,
            gap: gap, align: align, pad: pad
          )
          @app.command(:pack, child.realized.path, **opts)
        end
      end

      def flow_pack_opts(flow:, child:, index:, last_index:, gap:, align:, pad:)
        opts = { side: flow[:side] }
        opts[flow[:main_pad]] = [index.zero? ? pad : gap, index == last_index ? pad : 0]
        opts[flow[:cross_pad]] = pad

        grow = child.layout && child.layout[:grow]
        stretch = align == :stretch
        fills = [(flow[:main_fill] if grow), (flow[:cross_fill] if stretch)].compact
        opts[:fill] = fills.length == 2 ? 'both' : fills.first unless fills.empty?
        opts[:expand] = true if grow
        unless stretch
          opts[:anchor] = flow[:anchor].fetch(align) {
            raise ArgumentError, "invalid align: #{align.inspect} (expected :start, :center, :end, or :stretch)"
          }
        end

        opts
      end

      def wire_event(node, binding)
        target_node =
          if binding.target
            @document.find(binding.target) or
              raise ArgumentError, "event target :#{binding.target} not found in the document"
          else
            node
          end

        @app.bind(target_node.realized.path, binding.event, *binding.subs) { |*args| binding.handler.call(*args) }
      end

      def allocate_path(node, parent_path)
        segment = node.name ? node.name.to_s : next_auto_segment
        parent_path == '.' ? ".#{segment}" : "#{parent_path}.#{segment}"
      end

      def next_auto_segment
        @auto_segment_count += 1
        "w#{@auto_segment_count}"
      end
    end
  end
end
