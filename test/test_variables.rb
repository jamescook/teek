# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestVariables < Minitest::Test
  include TeekTestHelper

  tk_test "set_variable/get_variable round-trip" do
    app.set_variable('myvar', 'hello')
    assert_equal 'hello', app.get_variable('myvar')
  end

  tk_test "set_variable should overwrite existing value" do
    app.set_variable('x', 'first')
    app.set_variable('x', 'second')
    assert_equal 'second', app.get_variable('x')
  end

  tk_test "get_variable on nonexistent should raise" do
    assert_raises(Teek::TclError) { app.get_variable('does_not_exist_xyz') }
  end

  tk_test "variable should work with widget textvariable" do
    app.set_variable('lbl_text', 'initial')
    app.command('ttk::label', '.lbl', textvariable: :lbl_text)

    assert_equal 'initial', app.tcl_eval('.lbl cget -text')

    app.set_variable('lbl_text', 'updated')
    assert_equal 'updated', app.tcl_eval('.lbl cget -text')
  end

  tk_test "set_variable should return the value" do
    assert_equal '42', app.set_variable('rv', '42')
  end

  # -- Tcl-special characters in values ------------------------------------
  #
  # set_variable/get_variable route through Interp#tcl_set_var/tcl_get_var
  # (Tcl_SetVar/Tcl_GetVar directly) rather than building a "set name {value}"
  # string and re-parsing it through the Tcl interpreter, so none of these
  # need any escaping on the Ruby side.

  tk_test "value with an unbalanced closing brace should round-trip" do
    app.set_variable('v_close_brace', 'a}b')
    assert_equal 'a}b', app.get_variable('v_close_brace')
  end

  tk_test "value with an unbalanced opening brace should round-trip" do
    app.set_variable('v_open_brace', 'a{b')
    assert_equal 'a{b', app.get_variable('v_open_brace')
  end

  tk_test "value ending with a backslash should round-trip" do
    app.set_variable('v_trailing_bs', 'C:\\path\\')
    assert_equal 'C:\\path\\', app.get_variable('v_trailing_bs')
  end

  tk_test "value containing a dollar sign should not be variable-substituted" do
    app.set_variable('some_other_var', 'SHOULD_NOT_APPEAR')
    app.set_variable('v_dollar', '$some_other_var')
    assert_equal '$some_other_var', app.get_variable('v_dollar')
  end

  tk_test "value containing brackets should not be command-substituted" do
    app.set_variable('v_bracket', '[set injection_target_var INJECTED]')
    assert_equal '[set injection_target_var INJECTED]', app.get_variable('v_bracket')
    assert_raises(Teek::TclError) { app.get_variable('injection_target_var') }
  end

  tk_test "value with spaces and embedded newlines should round-trip" do
    value = "line one\n  line two with spaces\nline three"
    app.set_variable('v_multiline', value)
    assert_equal value, app.get_variable('v_multiline')
  end

  tk_test "a value combining braces, backslash, $ and [ should round-trip byte-for-byte" do
    value = 'weird{value}\\with $vars and [brackets] and \\'
    app.set_variable('v_combo', value)
    assert_equal value, app.get_variable('v_combo')
  end

  # -- variable name forms --------------------------------------------------

  tk_test "array-element variable names should round-trip" do
    app.set_variable('arr(key1)', 'value1')
    app.set_variable('arr(key2)', 'value2')
    assert_equal 'value1', app.get_variable('arr(key1)')
    assert_equal 'value2', app.get_variable('arr(key2)')
  end

  tk_test "fully-qualified namespaced variable names should round-trip" do
    app.tcl_eval('namespace eval ::teekbfmtest {}')
    app.set_variable('::teekbfmtest::v1', 'nsvalue')
    assert_equal 'nsvalue', app.get_variable('::teekbfmtest::v1')
  end

  # -- non-string name/value (real call sites pass Integers, e.g. progress %) --

  tk_test "set_variable should coerce a non-String value, matching existing call sites" do
    app.set_variable('v_int', 42)
    assert_equal '42', app.get_variable('v_int')
  end

  tk_test "set_variable should coerce a non-String name" do
    app.set_variable(:v_sym_name, 'ok')
    assert_equal 'ok', app.get_variable('v_sym_name')
  end
end
