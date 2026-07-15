# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/session'

# ui.component opens a fresh Scope around its block, so the SAME local
# name declared in two different components never collides - a plain
# threaded-builder method (def foo(ui) = ui.row { ... }) needs none of
# this and keeps working unchanged; ui.component is only for the
# opt-in case where scope isolation matters (reuse, avoiding name
# collisions across files).
class TestComponent < Minitest::Test
  def build_session
    Teek::UI::Session.new(title: 'Component Test')
  end

  def test_component_splices_its_subtree_under_the_current_parent
    session = build_session

    session.panel(:sidebar) { |p| p.component { |c| c.button(:save, text: 'Save') } }

    sidebar_node = session.document.root.children.first
    assert_equal :panel, sidebar_node.type
    assert_equal [:button], sidebar_node.children.map(&:type),
      "the component's own node should attach directly to :sidebar, with no extra wrapper container"
  end

  def test_the_same_local_name_in_two_different_components_does_not_collide
    session = build_session

    session.component { |c| c.button(:save, text: 'Save A') }
    session.component { |c| c.button(:save, text: 'Save B') }

    # neither #component call raised - that's the assertion. Confirm both
    # nodes actually exist, independently, under the document root.
    assert_equal 2, session.document.root.children.length
    assert_equal ['Save A', 'Save B'], session.document.root.children.map { |n| n.opts[:text] }
  end

  def test_ui_bracket_inside_a_component_resolves_to_that_components_own_node
    session = build_session
    inner_lookup = nil

    session.component do |c|
      c.button(:save, text: 'Save')
      inner_lookup = c[:save]
    end

    refute_nil inner_lookup
    assert_equal :button, inner_lookup.type
  end

  def test_ui_bracket_inside_a_component_does_not_see_a_top_level_node_of_the_same_name
    session = build_session
    session.button(:save, text: 'Top-level Save')
    inner_lookup = :not_set

    session.component { |c| inner_lookup = c[:save] }

    assert_nil inner_lookup, "a component's ui[:save] should not resolve to an unrelated top-level :save"
  end

  def test_ui_bracket_outside_any_component_does_not_see_a_components_node
    session = build_session

    session.component { |c| c.button(:save, text: 'Component Save') }

    assert_nil session[:save], "top-level ui[:save] should not resolve into a component's own scope"
  end

  def test_ui_bracket_at_top_level_is_unaffected_by_components_existing
    session = build_session
    session.button(:go, text: 'Go')
    session.component { |c| c.button(:save, text: 'Save') }

    handle = session[:go]

    refute_nil handle
    assert_equal :button, handle.type
  end

  def test_two_components_can_use_the_same_label_without_colliding
    session = build_session

    session.component(:row) { |c| c.button(:save, text: 'First') }
    session.component(:row) { |c| c.button(:save, text: 'Second') }

    assert_equal 2, session.document.root.children.length
    assert_equal ['First', 'Second'], session.document.root.children.map { |n| n.opts[:text] }
  end

  def test_threaded_builder_style_still_works_with_no_component_call_at_all
    session = build_session
    toolbar = ->(ui) { ui.row { |r| r.button(:save, text: 'Save') } }

    session.panel(:p) { |p| toolbar.call(p) }

    assert_equal :button, session[:save].type
  end

  def test_component_requires_no_tk_interpreter_to_exercise
    session = build_session

    session.component { |c| c.button(:save, text: 'Save') }

    # reaching this line with no Teek::App/interpreter involved anywhere
    # above IS the assertion - scoping is pure Ruby.
    assert session.document.root.children.any?
  end
end
