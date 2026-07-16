# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'
require 'teek/ui/node'
require 'teek/ui/realized_node'
require 'teek/ui/menu_entry_addressing'

# MenuEntryAddressing is the WidgetType#addressing strategy for :menu_item/
# :menu_checkbox/:menu_radio - a menu entry has no independent Tk path of
# its own, only the enclosing menu does, so this resolves the entry's
# CURRENT position fresh on every call via Node#parent instead of caching
# an index (Tk menu entries are addressed purely by numeric index, and
# TkMenu.c renumbers every entry after the one that changed).
class TestMenuEntryAddressing < Minitest::Test
  include TeekTestHelper

  def test_virtual_path_marks_past_the_real_tk_path
    menu_node = Teek::UI::Node.new(type: :menu, name: :file_menu)
    menu_node.realized = Teek::UI::RealizedNode.new(app: :fake_app, path: '.menu_bar.file_menu')
    entry = menu_node.add_child(Teek::UI::Node.new(type: :menu_item, name: :quick_load))

    addressing = Teek::UI::MenuEntryAddressing.new(entry)

    assert_equal '.menu_bar.file_menu!quick_load', addressing.virtual_path
  end

  def test_configure_raises_before_the_parent_menu_is_realized
    menu_node = Teek::UI::Node.new(type: :menu, name: :file_menu)
    entry = menu_node.add_child(Teek::UI::Node.new(type: :menu_item, name: :quick_load))

    addressing = Teek::UI::MenuEntryAddressing.new(entry)

    assert_raises(Teek::UI::NotRealizedError) { addressing.configure(state: :disabled) }
  end

  def test_configure_targets_the_live_current_index_immune_to_earlier_sibling_removal
    assert_tk_app("configure should entryconfigure the entry at its CURRENT live index, not a stale cached one") do
      require 'teek/ui/node'
      require 'teek/ui/realized_node'
      require 'teek/ui/menu_entry_addressing'

      menu_path = '.testmenu1'
      app.menu(menu_path)
      app.command(menu_path, :add, :command, label: 'First')
      app.command(menu_path, :add, :command, label: 'Second')
      app.command(menu_path, :add, :command, label: 'Third')

      menu_node = Teek::UI::Node.new(type: :menu, name: :testmenu1)
      menu_node.realized = Teek::UI::RealizedNode.new(app: app, path: menu_path)

      first_entry = menu_node.add_child(Teek::UI::Node.new(type: :menu_item, name: :first))
      menu_node.add_child(Teek::UI::Node.new(type: :menu_item, name: :second))
      third_entry = menu_node.add_child(Teek::UI::Node.new(type: :menu_item, name: :third))

      # Removing First shifts Second and Third down one live index each -
      # Tk itself renumbers around the delete; nothing in teek does the
      # shifting. Node#parent.children.index(node) just re-reads whatever
      # the CURRENT position is, so it's automatically correct with no
      # bookkeeping - a stale index cached at creation time (2, for Third)
      # would now be wrong.
      app.command(menu_path, :delete, 0)
      menu_node.children.delete(first_entry)

      Teek::UI::MenuEntryAddressing.new(third_entry).configure(state: :disabled)

      assert_equal 'disabled', app.tcl_eval("#{menu_path} entrycget 1 -state"),
        "Third's live index is now 1 (after First was removed) - entry 1 should be disabled"
      assert_equal 'normal', app.tcl_eval("#{menu_path} entrycget 0 -state"),
        "Second's live index is now 0 - it should be untouched"
    end
  end
end
