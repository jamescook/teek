# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/node'

class TestNode < Minitest::Test
  def test_defaults
    node = Teek::UI::Node.new(type: :button)

    assert_equal :button, node.type
    assert_nil node.name
    assert_nil node.key
    assert_equal({}, node.opts)
    assert_equal [], node.children
    assert_equal [], node.events
    assert_nil node.layout
    assert_nil node.realized
  end

  def test_key_defaults_to_the_name_when_no_key_given
    node = Teek::UI::Node.new(type: :button, name: :save)

    assert_equal 'save', node.key
  end

  def test_explicit_key_overrides_the_name_derived_default
    node = Teek::UI::Node.new(type: :button, name: :save, key: 'custom')

    assert_equal 'custom', node.key
  end

  def test_opts_are_retained_verbatim
    node = Teek::UI::Node.new(type: :label, opts: { text: 'Hi', width: 10 })

    assert_equal({ text: 'Hi', width: 10 }, node.opts)
  end

  def test_add_child_appends_and_returns_the_child
    parent = Teek::UI::Node.new(type: :column)
    child = Teek::UI::Node.new(type: :button)

    result = parent.add_child(child)

    assert_equal [child], parent.children
    assert_same child, result
  end

  def test_layout_and_realized_are_settable_after_construction
    node = Teek::UI::Node.new(type: :button)

    node.layout = { grow: true }
    node.realized = :fake_handle

    assert_equal({ grow: true }, node.layout)
    assert_equal :fake_handle, node.realized
  end

  def test_each_visits_self_then_children_depth_first_preorder
    root = Teek::UI::Node.new(type: :column)
    a = root.add_child(Teek::UI::Node.new(type: :button, name: :a))
    b = root.add_child(Teek::UI::Node.new(type: :column, name: :b))
    c = b.add_child(Teek::UI::Node.new(type: :button, name: :c))

    visited = []
    root.each { |n| visited << n }

    assert_equal [root, a, b, c], visited
  end

  def test_each_without_a_block_returns_an_enumerator
    root = Teek::UI::Node.new(type: :column)
    root.add_child(Teek::UI::Node.new(type: :button, name: :a))

    assert_equal [:column, :button], root.each.map(&:type)
  end
end
