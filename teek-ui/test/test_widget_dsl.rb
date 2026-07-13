# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/session'

class TestWidgetDsl < Minitest::Test
  LEAF_WIDGET_TYPES = %i[
    text_box text_area label button checkbox radio slider dropdown
    number_box list table tree progress divider
  ].freeze

  def build_session
    Teek::UI::Session.new(title: 'Widget DSL Test')
  end

  def test_each_leaf_widget_method_appends_a_node_of_the_matching_type
    LEAF_WIDGET_TYPES.each do |method|
      session = build_session

      handle = session.send(method, :w, text: 'x')

      node = session.document.root.children.first
      assert_equal method, node.type, "##{method} should create a :#{method} node"
      assert_equal({ text: 'x' }, node.opts)
      assert_kind_of Teek::UI::Handle, handle
      assert_equal method, handle.type
    end
  end

  def test_leaf_widgets_work_unnamed
    session = build_session

    session.label(text: 'Hi')

    node = session.document.root.children.first
    assert_equal :label, node.type
    assert_nil node.name
    refute_nil node.key
  end

  def test_named_widget_is_addressable_via_bracket_lookup
    session = build_session

    session.text_box(:query)

    handle = session[:query]
    assert_kind_of Teek::UI::Handle, handle
    assert_equal :text_box, handle.type
    assert_equal :query, handle.name
  end

  def test_bracket_lookup_returns_nil_for_an_unknown_name
    session = build_session

    assert_nil session[:nope]
  end

  def test_duplicate_name_raises_through_the_dsl
    session = build_session
    session.button(:save)

    assert_raises(ArgumentError) { session.button(:save) }
  end

  def test_panel_nests_children_declared_in_its_block
    session = build_session

    session.panel(:controls) do |p|
      p.button(:go, text: 'Go')
      p.button(:stop, text: 'Stop')
    end

    panel_node = session.document.root.children.first
    assert_equal :panel, panel_node.type
    assert_equal [:button, :button], panel_node.children.map(&:type)
    assert_equal [:go, :stop], panel_node.children.map(&:name)
  end

  def test_container_block_yields_the_same_session_object
    session = build_session
    yielded = nil

    session.panel(:controls) { |p| yielded = p }

    # not a separate scoped builder - the same object, so a name declared
    # inside the block is addressable from outside it too via ui[:name]
    assert_same session, yielded
  end

  def test_nested_containers_attach_at_the_correct_depth
    session = build_session

    session.panel(:outer) do |outer|
      outer.panel(:inner) do |inner|
        inner.button(:deep)
      end
    end

    outer_node = session.document.root.children.first
    inner_node = outer_node.children.first
    deep_node = inner_node.children.first

    assert_equal :panel, outer_node.type
    assert_equal :panel, inner_node.type
    assert_equal :button, deep_node.type
    assert_equal [], deep_node.children
  end

  def test_a_container_without_a_block_still_creates_a_childless_node
    session = build_session

    session.window(:settings, title: 'Settings')

    node = session.document.root.children.first
    assert_equal :window, node.type
    assert_equal [], node.children
  end

  def test_box_is_a_synonym_for_panel
    session = build_session

    session.box(:sidebar)

    node = session.document.root.children.first
    assert_equal :panel, node.type
  end

  %i[group canvas window].each do |container|
    define_method("test_#{container}_is_a_container_that_nests_children") do
      session = build_session

      session.send(container, :c) { |b| b.label(:inner_label) }

      node = session.document.root.children.first
      assert_equal container, node.type
      assert_equal [:label], node.children.map(&:type)
    end
  end

  def test_var_is_tracked_on_the_session
    session = build_session

    speed = session.var(5)

    assert_kind_of Teek::UI::Var, speed
    assert_includes session.vars, speed
  end

  def test_var_names_are_unique_within_a_session
    session = build_session

    a = session.var(1)
    b = session.var(2)

    refute_equal a.name, b.name
  end

  def test_bind_translates_to_the_variable_option_for_a_slider
    session = build_session
    speed = session.var(5)

    session.slider(:s, from: 1, to: 10, bind: speed)

    node = session.document.root.children.first
    assert_equal speed.name, node.opts[:variable]
    refute node.opts.key?(:bind), "bind: should not leak through to the realized widget options"
  end

  def test_bind_translates_to_the_textvariable_option_for_a_text_box
    session = build_session
    speed = session.var(5)

    session.text_box(:t, bind: speed)

    node = session.document.root.children.first
    assert_equal speed.name, node.opts[:textvariable]
  end

  def test_bind_on_an_unsupported_widget_type_raises
    session = build_session
    speed = session.var(5)

    assert_raises(ArgumentError) { session.divider(:d, bind: speed) }
  end
end
