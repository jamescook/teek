# frozen_string_literal: true

# Tests for callback control flow via throw/catch.
#
# throw :teek_break    → TCL_BREAK   (stops event propagation)
# throw :teek_continue → TCL_CONTINUE
# throw :teek_return   → TCL_RETURN

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestCallbackControlFlow < Minitest::Test
  include TeekTestHelper

  def test_break_stops_event_propagation
    assert_tk_app("throw :teek_break should stop event propagation") do
      first_fired = false
      second_fired = false

      app.show
      app.tcl_eval("entry .e")
      app.tcl_eval("pack .e")

      app.bind('.e', 'Key-a') {
        first_fired = true
        throw :teek_break
      }

      app.bind('Entry', 'Key-a') { second_fired = true }

      app.tcl_eval("focus -force .e")
      app.update
      app.tcl_eval("event generate .e <Key-a>")
      app.update

      assert first_fired, "first callback did not fire"
      refute second_fired, "second callback fired despite break"

      app.unbind('Entry', 'Key-a')
    end
  end

  def test_return_does_not_crash
    assert_tk_app("throw :teek_return should not crash") do
      fired = false

      cb = app.register_callback(proc { |*|
        fired = true
        throw :teek_return
      })

      app.tcl_eval("button .b_ret -command {ruby_callback #{cb}}")
      app.tcl_eval(".b_ret invoke")

      assert fired, "callback did not fire"
    end
  end

  def test_normal_callback_unaffected
    assert_tk_app("normal callback should work") do
      result = nil

      cb = app.register_callback(proc { |*|
        result = "hello"
      })

      app.tcl_eval("button .b_norm -command {ruby_callback #{cb}}")
      app.tcl_eval(".b_norm invoke")

      assert_equal "hello", result
    end
  end

  def test_real_exception_is_tcl_error
    assert_tk_app("real exception should become Tcl error") do
      cb = app.register_callback(proc { |*|
        raise "boom"
      })

      result = app.tcl_eval("catch {ruby_callback #{cb}} errmsg")
      assert_equal "1", result

      assert_includes app.get_variable('errmsg'), "boom"
    end
  end
end
