# frozen_string_literal: true

require_relative 'errors'

module Teek
  module UI
    # @api private
    #
    # The {WidgetType#addressing} strategy for :menu_item/:menu_checkbox/
    # :menu_radio - a menu entry has no independent Tk path of its own,
    # only the enclosing menu does. #configure resolves the entry's
    # CURRENT position fresh on every call via {Node#parent} rather than
    # caching an index, so an earlier sibling being inserted or removed
    # can never leave this addressing the wrong entry (Tk menu entries
    # are addressed purely by numeric index, and TkMenu.c renumbers every
    # entry after the one that changed).
    class MenuEntryAddressing
      # @api private
      def initialize(node)
        @node = node
      end

      # @return [String] the parent menu's real path, marked past the
      #   point a real Tk path stops applying - +!+ is illegal in a Tk
      #   path segment, so handing this to a raw Tk command fails loudly
      #   (an "invalid command name" Tcl error) instead of silently
      #   misbehaving.
      def virtual_path
        "#{menu.path}!#{@node.name || @node.key}"
      end

      # @param opts [Hash]
      # @return [void]
      # @raise [NotRealizedError] before the parent menu is realized
      def configure(**opts)
        menu.app.command(menu.path, :entryconfigure, current_index, **opts)
      end

      private

      def menu
        @node.parent&.realized or raise NotRealizedError
      end

      # The Document tree's own child order exactly matches the live
      # menu's entry order - {Realizer#create_menu_tree} adds every
      # child, in order, with one Tk `add` call each - so no live re-scan
      # of the menu is needed to find this entry's current position.
      def current_index
        @node.parent.children.index(@node)
      end
    end
  end
end
