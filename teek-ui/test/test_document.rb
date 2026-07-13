# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/document'

class TestDocument < Minitest::Test
  def test_root_is_an_empty_root_node
    document = Teek::UI::Document.new

    assert_kind_of Teek::UI::Node, document.root
    assert_equal :root, document.root.type
    assert_equal [], document.root.children
  end

  def test_create_builds_a_node_but_does_not_attach_it_to_any_parent
    document = Teek::UI::Document.new

    node = document.create(type: :button, opts: { text: 'Go' })

    assert_equal :button, node.type
    assert_equal({ text: 'Go' }, node.opts)
    assert_equal [], document.root.children, "create should not attach the node anywhere - the caller decides the parent"
  end

  def test_named_node_is_findable_by_symbol_after_attaching
    document = Teek::UI::Document.new
    node = document.create(type: :button, name: :save)
    document.root.add_child(node)

    assert_same node, document.find(:save)
    assert_same node, document[:save]
  end

  def test_find_returns_nil_for_an_unknown_name
    document = Teek::UI::Document.new

    assert_nil document.find(:nope)
    assert_nil document[:nope]
  end

  def test_unnamed_nodes_get_a_distinct_auto_generated_key
    document = Teek::UI::Document.new

    a = document.create(type: :button)
    b = document.create(type: :button)

    refute_nil a.key
    refute_nil b.key
    refute_equal a.key, b.key
  end

  def test_named_node_key_is_the_name
    document = Teek::UI::Document.new

    node = document.create(type: :button, name: :save)

    assert_equal 'save', node.key
  end

  def test_duplicate_explicit_name_is_detected
    document = Teek::UI::Document.new
    document.create(type: :button, name: :save)

    error = assert_raises(ArgumentError) { document.create(type: :button, name: :save) }
    assert_match(/save/, error.message)
  end

  def test_each_node_traverses_the_whole_tree_from_root
    document = Teek::UI::Document.new
    a = document.create(type: :button, name: :a)
    b = document.create(type: :column, name: :b)
    c = document.create(type: :button, name: :c)
    document.root.add_child(a)
    document.root.add_child(b)
    b.add_child(c)

    visited = []
    document.each_node { |n| visited << n }

    assert_equal [document.root, a, b, c], visited
  end
end
