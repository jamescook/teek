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
    # @note Layout is a placeholder for now: +link+ just packs each node's
    #   children top-to-bottom with no options. There's no layout DSL yet
    #   (gap/align/grow), so there's nothing richer to apply - once it
    #   exists, +link+ needs to consult +node.layout+ instead of packing
    #   unconditionally.
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
          @app.command(tk_command, path, **node.opts)
          node.realized = RealizedNode.new(app: @app, path: path)
        end

        node.children.each { |child| create(child, path) }
      end

      def link(node)
        node.children.each { |child| @app.command(:pack, child.realized.path) }
        node.events.each { |binding| wire_event(node, binding) }
        node.children.each { |child| link(child) }
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
