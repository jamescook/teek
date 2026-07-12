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

  # -- Tcl-special characters in values ------------------------------------
  #
  # set_variable/get_variable route through Interp#tcl_set_var/tcl_get_var
  # (Tcl_SetVar/Tcl_GetVar directly) rather than building a "set name {value}"
  # string and re-parsing it through the Tcl interpreter, so none of these
  # need any escaping on the Ruby side.

  def test_round_trip_value_with_unbalanced_closing_brace
    assert_tk_app("value with an unbalanced closing brace should round-trip") do
      app.set_variable('v_close_brace', 'a}b')
      assert_equal 'a}b', app.get_variable('v_close_brace')
    end
  end

  def test_round_trip_value_with_unbalanced_opening_brace
    assert_tk_app("value with an unbalanced opening brace should round-trip") do
      app.set_variable('v_open_brace', 'a{b')
      assert_equal 'a{b', app.get_variable('v_open_brace')
    end
  end

  def test_round_trip_value_with_trailing_backslash
    assert_tk_app("value ending with a backslash should round-trip") do
      app.set_variable('v_trailing_bs', 'C:\\path\\')
      assert_equal 'C:\\path\\', app.get_variable('v_trailing_bs')
    end
  end

  def test_round_trip_value_with_dollar_sign
    assert_tk_app("value containing a dollar sign should not be variable-substituted") do
      app.set_variable('some_other_var', 'SHOULD_NOT_APPEAR')
      app.set_variable('v_dollar', '$some_other_var')
      assert_equal '$some_other_var', app.get_variable('v_dollar')
    end
  end

  def test_round_trip_value_with_square_bracket_command_substitution
    assert_tk_app("value containing brackets should not be command-substituted") do
      app.set_variable('v_bracket', '[set injection_target_var INJECTED]')
      assert_equal '[set injection_target_var INJECTED]', app.get_variable('v_bracket')
      assert_raises(Teek::TclError) { app.get_variable('injection_target_var') }
    end
  end

  def test_round_trip_value_with_spaces_and_newlines
    assert_tk_app("value with spaces and embedded newlines should round-trip") do
      value = "line one\n  line two with spaces\nline three"
      app.set_variable('v_multiline', value)
      assert_equal value, app.get_variable('v_multiline')
    end
  end

  def test_round_trip_value_combining_multiple_special_characters
    assert_tk_app("a value combining braces, backslash, $ and [ should round-trip byte-for-byte") do
      value = 'weird{value}\\with $vars and [brackets] and \\'
      app.set_variable('v_combo', value)
      assert_equal value, app.get_variable('v_combo')
    end
  end

  # -- variable name forms --------------------------------------------------

  def test_array_element_name_round_trip
    assert_tk_app("array-element variable names should round-trip") do
      app.set_variable('arr(key1)', 'value1')
      app.set_variable('arr(key2)', 'value2')
      assert_equal 'value1', app.get_variable('arr(key1)')
      assert_equal 'value2', app.get_variable('arr(key2)')
    end
  end

  def test_namespaced_variable_name_round_trip
    assert_tk_app("fully-qualified namespaced variable names should round-trip") do
      app.tcl_eval('namespace eval ::teekbfmtest {}')
      app.set_variable('::teekbfmtest::v1', 'nsvalue')
      assert_equal 'nsvalue', app.get_variable('::teekbfmtest::v1')
    end
  end

  # -- non-string name/value (real call sites pass Integers, e.g. progress %) --

  def test_set_variable_coerces_non_string_value
    assert_tk_app("set_variable should coerce a non-String value, matching existing call sites") do
      app.set_variable('v_int', 42)
      assert_equal '42', app.get_variable('v_int')
    end
  end

  def test_set_variable_coerces_symbol_name
    assert_tk_app("set_variable should coerce a non-String name") do
      app.set_variable(:v_sym_name, 'ok')
      assert_equal 'ok', app.get_variable('v_sym_name')
    end
  end
end
