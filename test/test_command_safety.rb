# frozen_string_literal: true

# Tests for App#command's value marshalling - specifically, that a value
# reaches Tk verbatim regardless of what Tcl-special characters it
# contains. raw_command (the shared builder underneath #command and
# every interceptor) used to brace-quote each value and hand the joined
# string to tcl_eval; a value with unbalanced braces breaks that outright
# (Tcl's parser treats the extra brace as ending or extending the group).
# It now builds a plain argv array and hands it to tcl_invoke
# (Tcl_EvalObjv - no string parsing at all), so nothing needs escaping.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestCommandSafety < Minitest::Test
  include TeekTestHelper

  tk_test "a value with an unbalanced close brace should round-trip through a kwarg" do
    value = 'hello } world'
    app.command(:label, '.lbl1', text: value)

    assert_equal value, app.command('.lbl1', :cget, '-text')
  end

  tk_test "a value with an unbalanced open brace should round-trip through a kwarg" do
    value = 'hello { world'
    app.command(:label, '.lbl2', text: value)

    assert_equal value, app.command('.lbl2', :cget, '-text')
  end

  tk_test "a literal $ in a kwarg value should not be treated as a Tcl variable reference" do
    value = 'cost: $5'
    app.command(:label, '.lbl3', text: value)

    assert_equal value, app.command('.lbl3', :cget, '-text')
  end

  tk_test "literal square brackets in a kwarg value should not be treated as Tcl command substitution" do
    value = 'array[0] = [expr {1+1}]'
    app.command(:label, '.lbl4', text: value)

    assert_equal value, app.command('.lbl4', :cget, '-text')
  end

  tk_test "a newline in a kwarg value should round-trip through a kwarg" do
    value = "line1\nline2"
    app.command(:label, '.lbl5', text: value)

    assert_equal value, app.command('.lbl5', :cget, '-text')
  end

  tk_test "a value ending in a backslash should round-trip through a kwarg" do
    value = 'path\\'
    app.command(:label, '.lbl6', text: value)

    assert_equal value, app.command('.lbl6', :cget, '-text')
  end

  tk_test "a value combining every hazard at once should still round-trip correctly" do
    value = "unbalanced } brace, $var, [cmd sub]\nnewline, trailing\\"
    app.command(:label, '.lbl7', text: value)

    assert_equal value, app.command('.lbl7', :cget, '-text')
  end

  tk_test "a value with an unbalanced brace should round-trip through a positional arg" do
    value = 'hello } world'
    app.command(:text, '.txt1')
    app.command('.txt1', :insert, '1.0', value)

    assert_equal value, app.command('.txt1', :get, '1.0', 'end-1c')
  end

  tk_test "an Array kwarg value should become a well-formed Tcl list, round-tripping via split_list" do
    app.command('ttk::treeview', '.tv1', columns: ['col one', 'col2'])

    result = app.command('.tv1', :cget, '-columns')
    assert_equal ['col one', 'col2'], app.split_list(result)
  end

  tk_test "an Array kwarg value with hazardous elements should still round-trip via split_list" do
    app.command('ttk::treeview', '.tv2', columns: ['a } b', 'c$d'])

    result = app.command('.tv2', :cget, '-columns')
    assert_equal ['a } b', 'c$d'], app.split_list(result)
  end
end
