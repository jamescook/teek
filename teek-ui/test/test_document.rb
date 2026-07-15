# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/document'
require 'teek/ui/scope'

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

  def test_same_name_in_two_different_scopes_does_not_collide
    document = Teek::UI::Document.new
    scope_a = Teek::UI::Scope.new(:a)
    scope_b = Teek::UI::Scope.new(:b)

    a = document.create(type: :button, name: :save, scope: scope_a)
    b = document.create(type: :button, name: :save, scope: scope_b)

    refute_same a, b
    assert_same a, document.find(:save, scope: scope_a)
    assert_same b, document.find(:save, scope: scope_b)
  end

  def test_same_name_in_the_same_scope_still_collides
    document = Teek::UI::Document.new
    scope = Teek::UI::Scope.new(:a)
    document.create(type: :button, name: :save, scope: scope)

    error = assert_raises(ArgumentError) {
      document.create(type: :button, name: :save, scope: scope)
    }
    assert_match(/save/, error.message)
  end

  def test_scoped_name_does_not_collide_with_the_same_name_at_top_level
    document = Teek::UI::Document.new
    scope = Teek::UI::Scope.new(:a)

    top_level = document.create(type: :button, name: :save)
    scoped = document.create(type: :button, name: :save, scope: scope)

    refute_same top_level, scoped
    assert_same top_level, document.find(:save)
    assert_same scoped, document.find(:save, scope: scope)
  end

  def test_find_with_a_scope_does_not_find_a_top_level_node_of_the_same_name
    document = Teek::UI::Document.new
    document.create(type: :button, name: :save)

    assert_nil document.find(:save, scope: Teek::UI::Scope.new(:a))
  end

  def test_find_without_a_scope_does_not_find_a_scoped_node_of_the_same_name
    document = Teek::UI::Document.new
    document.create(type: :button, name: :save, scope: Teek::UI::Scope.new(:a))

    assert_nil document.find(:save)
  end

  def test_two_scopes_with_the_same_label_do_not_share_a_namespace
    document = Teek::UI::Document.new
    first = Teek::UI::Scope.new(:widget)
    second = Teek::UI::Scope.new(:widget)

    a = document.create(type: :button, name: :save, scope: first)
    b = document.create(type: :button, name: :save, scope: second)

    refute_same a, b
    assert_same a, document.find(:save, scope: first)
    assert_same b, document.find(:save, scope: second)
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
