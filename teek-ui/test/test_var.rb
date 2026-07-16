# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/var'

class TestVar < Minitest::Test
  def test_name_is_the_allocated_tcl_variable_name
    var = Teek::UI::Var.new('::teek_ui_var_1', 5)

    assert_equal '::teek_ui_var_1', var.name
  end

  def test_value_raises_before_realize
    var = Teek::UI::Var.new('::teek_ui_var_1', 5)

    assert_raises(Teek::UI::NotRealizedError) { var.value }
  end

  def test_value_assignment_raises_before_realize
    var = Teek::UI::Var.new('::teek_ui_var_1', 5)

    assert_raises(Teek::UI::NotRealizedError) { var.value = 6 }
  end

  def test_on_change_is_queueable_before_realize_and_returns_self
    var = Teek::UI::Var.new('::teek_ui_var_1', 5)

    result = var.on_change { |v| v }

    assert_same var, result
  end
end
