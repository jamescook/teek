# frozen_string_literal: true

require_relative 'handle'

module Teek
  module UI
    # The build surface inside a `menu_bar`/`menu`/`context_menu` block - a
    # separate, small vocabulary from {WidgetDSL} (deliberately NOT mixed
    # into {Session}/yielded as `self` the way ordinary containers are),
    # since menu entries reuse names ordinary widgets already own
    # (`checkbox`/`radio` are ttk widgets one level up, menu entry kinds one
    # level down here) - a shared receiver would collide.
    #
    # Menu structure realizes through {Realizer#create_menu_tree} rather
    # than the generic per-node widget-creation path: nothing here is a Tk
    # widget of its own except `#menu` (a nested cascade, itself a `menu`
    # command) - `#item`/`#separator`/`#checkbox`/`#radio` are just entries
    # added to their parent's menu path, with no live path or Handle of
    # their own.
    class MenuBuilder
      # @api private
      def initialize(document, stack)
        @document = document
        @stack = stack
      end

      # A nested cascade - recursive, so the same method builds both a
      # menu_bar's top-level dropdowns (File/Edit/...) and any submenu
      # nested inside one of those.
      # @param name [Symbol, nil]
      # @param label [String] the cascade's displayed label
      # @param opts [Hash] extra Tk menu-entry options (e.g. +underline:+)
      # @yieldparam m [MenuBuilder] this same builder, scoped to the new menu
      # @return [Handle]
      def menu(name = nil, label:, **opts, &block)
        node = @document.create(type: :menu, name: name, opts: opts.merge(label: label))
        @stack.last.add_child(node)

        if block
          @stack.push(node)
          begin
            block.call(self)
          ensure
            @stack.pop
          end
        end

        Handle.new(node)
      end

      # A command entry.
      # @param label [String]
      # @param opts [Hash] extra Tk menu-entry options (e.g. +accelerator:+)
      # @yield called when the entry is invoked
      # @return [nil]
      def item(label:, **opts, &block)
        opts = opts.merge(command: block) if block
        append_entry(:menu_item, opts.merge(label: label))
        nil
      end

      # A separator entry.
      # @return [nil]
      def separator
        append_entry(:menu_separator, {})
        nil
      end

      # A checkbutton entry, bound to a reactive {Var} - ticked when the
      # var is true, unticked when false, the same +bind:+ convention
      # {WidgetDSL}'s own `checkbox` widget uses.
      # @param label [String]
      # @param bind [Var]
      # @param opts [Hash] extra Tk menu-entry options
      # @return [nil]
      def checkbox(label:, bind:, **opts)
        append_entry(:menu_checkbox, opts.merge(label: label, bind: bind))
        nil
      end

      # A radiobutton entry - `bind:` is shared across every radio entry in
      # the group, `value:` is what this one entry sets it to when chosen.
      # @param label [String]
      # @param bind [Var]
      # @param value [Object]
      # @param opts [Hash] extra Tk menu-entry options
      # @return [nil]
      def radio(label:, bind:, value:, **opts)
        append_entry(:menu_radio, opts.merge(label: label, bind: bind, value: value))
        nil
      end

      private

      def append_entry(type, opts)
        node = @document.create(type: type, opts: opts)
        @stack.last.add_child(node)
        node
      end
    end
  end
end
