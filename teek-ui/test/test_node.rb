# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/node'
require 'teek/ui/scope'

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
    assert_same Teek::UI::Scope::TOP_LEVEL, node.scope
  end

  def test_scope_is_settable_and_readable
    scope = Teek::UI::Scope.new(:sidebar)
    node = Teek::UI::Node.new(type: :button, scope: scope)

    assert_same scope, node.scope
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

  def test_add_child_sets_the_childs_parent
    parent = Teek::UI::Node.new(type: :column)
    child = Teek::UI::Node.new(type: :button)

    parent.add_child(child)

    assert_same parent, child.parent
  end

  def test_document_defaults_to_nil
    node = Teek::UI::Node.new(type: :button)

    assert_nil node.document
  end

  def test_document_is_settable_at_construction
    fake_document = Object.new
    node = Teek::UI::Node.new(type: :button, document: fake_document)

    assert_same fake_document, node.document
  end

  def test_remove_child_removes_it_from_the_parents_children
    parent = Teek::UI::Node.new(type: :column)
    a = parent.add_child(Teek::UI::Node.new(type: :button, name: :a))
    b = parent.add_child(Teek::UI::Node.new(type: :button, name: :b))

    parent.remove_child(a)

    assert_equal [b], parent.children
  end

  def test_remove_child_clears_the_removed_nodes_own_parent
    parent = Teek::UI::Node.new(type: :column)
    child = parent.add_child(Teek::UI::Node.new(type: :button))

    parent.remove_child(child)

    assert_nil child.parent
  end

  def test_remove_child_returns_the_removed_node
    parent = Teek::UI::Node.new(type: :column)
    child = parent.add_child(Teek::UI::Node.new(type: :button))

    result = parent.remove_child(child)

    assert_same child, result
  end

  def test_parent_is_nil_before_being_attached
    node = Teek::UI::Node.new(type: :button)

    assert_nil node.parent
  end

  def test_parent_setter_is_not_publicly_callable
    node = Teek::UI::Node.new(type: :button)

    assert_raises(NoMethodError) { node.parent = Teek::UI::Node.new(type: :column) }
  end

  def test_root_logical_path_is_a_bare_dot
    root = Teek::UI::Node.new(type: :root)

    assert_equal '.', root.logical_path
  end

  def test_logical_path_for_a_top_level_named_node
    root = Teek::UI::Node.new(type: :root)
    child = root.add_child(Teek::UI::Node.new(type: :button, name: :save))

    assert_equal '.save', child.logical_path
  end

  def test_logical_path_nests_through_named_ancestors
    root = Teek::UI::Node.new(type: :root)
    column = root.add_child(Teek::UI::Node.new(type: :column, name: :toolbar))
    button = column.add_child(Teek::UI::Node.new(type: :button, name: :save))

    assert_equal '.toolbar.save', button.logical_path
  end

  def test_logical_path_uses_the_auto_generated_key_when_unnamed
    root = Teek::UI::Node.new(type: :root)
    child = root.add_child(Teek::UI::Node.new(type: :button, key: '#anon1'))

    assert_equal '.#anon1', child.logical_path
  end

  def test_logical_path_of_an_unattached_node_treats_it_as_top_level
    node = Teek::UI::Node.new(type: :button, name: :save)

    assert_equal '.save', node.logical_path
  end
end
