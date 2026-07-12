# frozen_string_literal: true

# Tests for Teek::TclError carrying Tcl's errorInfo/errorCode, not just the
# short one-line Tcl_GetStringResult. Both interp entry points
# (tcl_eval/tcl_invoke, via App#tcl_eval/App#command) go through the same
# C-level raise path, so tcl_eval alone is enough to exercise it.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestTclErrors < Minitest::Test
  include TeekTestHelper

  def test_plain_error_message_is_still_the_short_result
    assert_tk_app("a failing eval should still raise with the short Tcl result as the message") do
      err = assert_raises(Teek::TclError) { app.tcl_eval("error {boom}") }
      assert_equal "boom", err.message
    end
  end

  def test_tcl_backtrace_captures_nested_call_stack
    assert_tk_app("a failing nested proc call should populate a multi-frame tcl_backtrace") do
      app.tcl_eval(<<~TCL)
        proc ::teek_test_inner {} { error "boom" }
        proc ::teek_test_outer {} { ::teek_test_inner }
      TCL

      err = assert_raises(Teek::TclError) { app.tcl_eval("::teek_test_outer") }

      refute_nil err.tcl_backtrace, "tcl_backtrace should be populated"
      assert_match(/teek_test_inner/, err.tcl_backtrace)
      assert_match(/invoked from within/, err.tcl_backtrace,
        "backtrace should show the outer proc's call site, not just the innermost error")
    end
  end

  def test_tcl_error_code_captures_custom_code
    assert_tk_app("a failing eval with an explicit errorCode should populate tcl_error_code") do
      err = assert_raises(Teek::TclError) { app.tcl_eval('error "boom" "" {MYAPP BAD_THING}') }

      assert_equal "MYAPP BAD_THING", err.tcl_error_code
    end
  end

  def test_tcl_error_code_defaults_to_none_when_not_set
    assert_tk_app("a failing eval without an explicit errorCode should report Tcl's default NONE") do
      err = assert_raises(Teek::TclError) { app.tcl_eval("error {boom}") }

      assert_equal "NONE", err.tcl_error_code
    end
  end

  def test_tcl_invoke_also_populates_backtrace_and_error_code
    assert_tk_app("a failing tcl_invoke call should populate the same accessors as tcl_eval") do
      app.tcl_eval('proc ::teek_test_invoke_fail {} { error "boom" "" {MYAPP INVOKE} }')

      err = assert_raises(Teek::TclError) { app.tcl_invoke("::teek_test_invoke_fail") }

      assert_equal "boom", err.message
      assert_equal "MYAPP INVOKE", err.tcl_error_code
      refute_nil err.tcl_backtrace
    end
  end
end
