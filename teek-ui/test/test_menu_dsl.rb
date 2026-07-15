# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/session'

class TestMenuDsl < Minitest::Test
  def build_session
    Teek::UI::Session.new(title: 'Menu DSL Test')
  end

  def test_menu_bar_creates_a_menu_bar_node_at_the_top_level
    session = build_session

    handle = session.menu_bar { |mb| mb.menu(label: 'File') }

    node = session.document.root.children.first
    assert_equal :menu_bar, node.type
    assert_kind_of Teek::UI::Handle, handle
    assert_equal :menu_bar, handle.type
  end

  def test_menu_bar_is_addressable_when_named
    session = build_session

    session.menu_bar(:mb) { |mb| mb.menu(label: 'File') }

    handle = session[:mb]
    assert_kind_of Teek::UI::Handle, handle
    assert_equal :menu_bar, handle.type
  end

  def test_menu_bar_raises_when_declared_inside_a_regular_container
    session = build_session

    error = assert_raises(ArgumentError) do
      session.panel(:p) { |p| p.menu_bar { |mb| mb.menu(label: 'File') } }
    end
    assert_match(/menu_bar/, error.message)
  end

  def test_menu_bar_is_allowed_directly_inside_a_window
    session = build_session

    session.window(:settings) { |w| w.menu_bar { |mb| mb.menu(label: 'File') } }

    window_node = session.document.root.children.first
    menu_bar_node = window_node.children.first
    assert_equal :menu_bar, menu_bar_node.type
  end

  def test_menu_declares_a_nested_cascade_node_with_a_label
    session = build_session

    session.menu_bar { |mb| mb.menu(label: 'File') }

    menu_bar_node = session.document.root.children.first
    file_node = menu_bar_node.children.first
    assert_equal :menu, file_node.type
    assert_equal 'File', file_node.opts[:label]
  end

  def test_menu_is_addressable_when_named
    session = build_session

    session.menu_bar { |mb| mb.menu(:file, label: 'File') }

    handle = session[:file]
    assert_kind_of Teek::UI::Handle, handle
    assert_equal :menu, handle.type
  end

  def test_menu_nests_recursively_for_submenus
    session = build_session

    session.menu_bar do |mb|
      mb.menu(label: 'File') do |file|
        file.menu(:recent, label: 'Recent') do |recent|
          recent.item(label: 'doc1.txt') { }
        end
      end
    end

    file_node = session.document.root.children.first.children.first
    recent_node = file_node.children.first
    assert_equal :menu, recent_node.type
    assert_equal 'Recent', recent_node.opts[:label]
    assert_equal [:menu_item], recent_node.children.map(&:type)
  end

  def test_item_appends_a_command_entry_with_a_command_block
    session = build_session
    fired = false

    session.menu_bar { |mb| mb.menu(label: 'File') { |f| f.item(label: 'Open') { fired = true } } }

    item_node = session.document.root.children.first.children.first.children.first
    assert_equal :menu_item, item_node.type
    assert_equal 'Open', item_node.opts[:label]
    item_node.opts[:command].call
    assert fired, "the item's block should be stashed as opts[:command]"
  end

  def test_item_is_addressable_when_named
    session = build_session

    session.menu_bar { |mb| mb.menu(label: 'File') { |f| f.item(:quick_load, label: 'Quick Load') { } } }

    handle = session[:quick_load]
    assert_kind_of Teek::UI::Handle, handle
    assert_equal :menu_item, handle.type
  end

  def test_item_returns_a_handle_even_when_unnamed
    session = build_session
    handle = nil

    session.menu_bar { |mb| mb.menu(label: 'File') { |f| handle = f.item(label: 'Open') { } } }

    assert_kind_of Teek::UI::Handle, handle
  end

  def test_item_without_a_block_has_no_command_opt
    session = build_session

    session.menu_bar { |mb| mb.menu(label: 'File') { |f| f.item(label: 'Disabled') } }

    item_node = session.document.root.children.first.children.first.children.first
    refute item_node.opts.key?(:command)
  end

  def test_item_passes_through_extra_opts_like_accelerator
    session = build_session

    session.menu_bar { |mb| mb.menu(label: 'File') { |f| f.item(label: 'Save', accelerator: 'Ctrl+S') { } } }

    item_node = session.document.root.children.first.children.first.children.first
    assert_equal 'Ctrl+S', item_node.opts[:accelerator]
  end

  def test_separator_appends_a_separator_entry
    session = build_session

    session.menu_bar { |mb| mb.menu(label: 'File') { |f| f.separator } }

    node = session.document.root.children.first.children.first.children.first
    assert_equal :menu_separator, node.type
    assert_equal({}, node.opts)
  end

  def test_checkbox_appends_a_checkbutton_entry_bound_to_a_var
    session = build_session
    wrap = session.var(true)

    session.menu_bar { |mb| mb.menu(label: 'Edit') { |e| e.checkbox(label: 'Word Wrap', bind: wrap) } }

    node = session.document.root.children.first.children.first.children.first
    assert_equal :menu_checkbox, node.type
    assert_equal 'Word Wrap', node.opts[:label]
    assert_same wrap, node.opts[:bind]
  end

  def test_checkbox_is_addressable_when_named
    session = build_session
    wrap = session.var(true)

    session.menu_bar { |mb| mb.menu(label: 'Edit') { |e| e.checkbox(:word_wrap, label: 'Word Wrap', bind: wrap) } }

    handle = session[:word_wrap]
    assert_kind_of Teek::UI::Handle, handle
    assert_equal :menu_checkbox, handle.type
  end

  def test_radio_is_addressable_when_named
    session = build_session
    size = session.var('small')

    session.menu_bar { |mb| mb.menu(label: 'Edit') { |e| e.radio(:small_size, label: 'Small', bind: size, value: 'small') } }

    handle = session[:small_size]
    assert_kind_of Teek::UI::Handle, handle
    assert_equal :menu_radio, handle.type
  end

  def test_radio_appends_a_radiobutton_entry_bound_to_a_var_with_a_value
    session = build_session
    size = session.var('small')

    session.menu_bar { |mb| mb.menu(label: 'Edit') { |e| e.radio(label: 'Small', bind: size, value: 'small') } }

    node = session.document.root.children.first.children.first.children.first
    assert_equal :menu_radio, node.type
    assert_equal 'small', node.opts[:value]
    assert_same size, node.opts[:bind]
  end

  def test_context_menu_creates_a_context_menu_node
    session = build_session

    handle = session.context_menu(:ctx) { |m| m.item(label: 'Delete') { } }

    node = session.document.root.children.first
    assert_equal :context_menu, node.type
    assert_kind_of Teek::UI::Handle, handle
    assert_equal :ctx, handle.name
  end

  def test_context_menu_can_hold_submenus_and_entries_like_any_menu
    session = build_session

    session.context_menu(:ctx) do |m|
      m.item(label: 'Delete') { }
      m.menu(label: 'Send to') { |sm| sm.item(label: 'Archive') { } }
    end

    ctx_node = session.document.root.children.first
    assert_equal %i[menu_item menu], ctx_node.children.map(&:type)
  end

  def test_menu_builder_does_not_expose_ordinary_widget_methods
    session = build_session

    session.menu_bar do |mb|
      # MenuBuilder is a distinct vocabulary, not the top-level widget DSL -
      # #checkbox/#radio here mean menu entries, not ttk::checkbutton/
      # ttk::radiobutton widgets, so it must not carry those methods too.
      refute mb.respond_to?(:button), "MenuBuilder should not carry the top-level widget vocabulary"
      assert mb.respond_to?(:checkbox), "MenuBuilder should define its own (menu-flavored) #checkbox"
    end
  end
end
