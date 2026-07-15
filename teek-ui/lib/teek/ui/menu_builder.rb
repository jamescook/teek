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
    # command) - `#item`/`#checkbox`/`#radio` are entries added to their
    # parent's menu path, with no live Tk path of their own, addressed via
    # their {WidgetType#addressing} strategy ({MenuEntryAddressing}) the
    # same way {Handle} resolves any other type's - see
    # {WidgetDSL#[]}. `#separator` stays unaddressable (nothing to
    # enable/disable/relabel on a divider).
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
      # @param name [Symbol, nil] for `ui[:name]` lookup - addressable
      #   later as a Handle (`.enable`/`.disable`/`.configure`)
      # @param label [String]
      # @param opts [Hash] extra Tk menu-entry options (e.g. +accelerator:+)
      # @yield called when the entry is invoked
      # @return [Handle]
      def item(name = nil, label:, **opts, &block)
        opts = opts.merge(command: block) if block
        Handle.new(append_entry(:menu_item, name, opts.merge(label: label)))
      end

      # A separator entry.
      # @return [nil]
      def separator
        append_entry(:menu_separator, nil, {})
        nil
      end

      # A checkbutton entry, bound to a reactive {Var} - ticked when the
      # var is true, unticked when false, the same +bind:+ convention
      # {WidgetDSL}'s own `checkbox` widget uses.
      # @param name [Symbol, nil] see {#item}
      # @param label [String]
      # @param bind [Var]
      # @param opts [Hash] extra Tk menu-entry options
      # @return [Handle]
      def checkbox(name = nil, label:, bind:, **opts)
        Handle.new(append_entry(:menu_checkbox, name, opts.merge(label: label, bind: bind)))
      end

      # A radiobutton entry - `bind:` is shared across every radio entry in
      # the group, `value:` is what this one entry sets it to when chosen.
      # @param name [Symbol, nil] see {#item}
      # @param label [String]
      # @param bind [Var]
      # @param value [Object]
      # @param opts [Hash] extra Tk menu-entry options
      # @return [Handle]
      def radio(name = nil, label:, bind:, value:, **opts)
        Handle.new(append_entry(:menu_radio, name, opts.merge(label: label, bind: bind, value: value)))
      end

      private

      def append_entry(type, name, opts)
        node = @document.create(type: type, name: name, opts: opts)
        @stack.last.add_child(node)
        node
      end
    end
  end
end
