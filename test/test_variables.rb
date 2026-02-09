# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestVariables < Minitest::Test
  include TeekTestHelper

  def test_set_and_get_variable
    assert_tk_app("set_variable/get_variable round-trip") do
      app.set_variable('myvar', 'hello')
      assert_equal 'hello', app.get_variable('myvar')
    end
  end

  def test_set_variable_overwrites
    assert_tk_app("set_variable should overwrite existing value") do
      app.set_variable('x', 'first')
      app.set_variable('x', 'second')
      assert_equal 'second', app.get_variable('x')
    end
  end

  def test_get_variable_nonexistent_raises
    assert_tk_app("get_variable on nonexistent should raise") do
      assert_raises(Teek::TclError) { app.get_variable('does_not_exist_xyz') }
    end
  end

  def test_variable_works_with_widget_textvariable
    assert_tk_app("variable should work with widget textvariable") do
      app.set_variable('lbl_text', 'initial')
      app.command('ttk::label', '.lbl', textvariable: :lbl_text)

      assert_equal 'initial', app.tcl_eval('.lbl cget -text')

      app.set_variable('lbl_text', 'updated')
      assert_equal 'updated', app.tcl_eval('.lbl cget -text')
    end
  end

  def test_set_variable_returns_value
    assert_tk_app("set_variable should return the value") do
      assert_equal '42', app.set_variable('rv', '42')
    end
  end
end
