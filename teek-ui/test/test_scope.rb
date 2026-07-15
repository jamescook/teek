# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/scope'

class TestScope < Minitest::Test
  def test_top_level_is_top_level
    assert Teek::UI::Scope::TOP_LEVEL.top_level?
  end

  def test_a_fresh_scope_is_not_top_level
    refute Teek::UI::Scope.new.top_level?
  end

  def test_two_scopes_with_the_same_label_are_never_the_same_scope
    a = Teek::UI::Scope.new(:widget)
    b = Teek::UI::Scope.new(:widget)

    refute a.equal?(b)
  end

  def test_parent_defaults_to_nil
    assert_nil Teek::UI::Scope.new.parent
  end

  def test_parent_is_settable
    parent = Teek::UI::Scope.new
    child = Teek::UI::Scope.new(:child, parent: parent)

    assert_same parent, child.parent
  end

  def test_label_is_readable
    scope = Teek::UI::Scope.new(:sidebar)

    assert_equal :sidebar, scope.label
  end
end
