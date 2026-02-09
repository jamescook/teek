# frozen_string_literal: true

# Tests for Ruby threading + Tk event loop interaction
#
# Key C functions exercised:
#   - lib_eventloop_core / lib_eventloop_launcher (update, after)
#   - ip_ruby_cmd (widget callbacks - Tcl calling Ruby)
#   - tcl_protect_core (exception handling)
#   - ip_eval_real, tk_funcall (Tcl eval round-trips)

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestThreading < Minitest::Test
  include TeekTestHelper

  def test_after_fires
    assert_tk_app("after callback should fire") do
      timer_fired = false
      app.after(50) { timer_fired = true }

      start = Time.now
      while Time.now - start < 0.3
        app.update
        sleep 0.01
      end

      assert timer_fired, "after callback did not fire"
    end
  end

  def test_ruby_thread_alongside_tk
    assert_tk_app("Ruby Thread should execute alongside Tk") do
      thread_result = nil
      t = Thread.new { thread_result = 42 }

      start = Time.now
      while Time.now - start < 0.3
        app.update
        sleep 0.01
      end

      t.join(1)
      assert_equal 42, thread_result, "Ruby Thread did not execute"
    end
  end

  def test_widget_callback
    assert_tk_app("Widget callback should fire via ip_ruby_cmd") do
      callback_fired = false
      app.command(:button, ".b_cb", command: proc { callback_fired = true })
      app.command(:pack, ".b_cb")
      app.command(".b_cb", "invoke")

      start = Time.now
      while Time.now - start < 0.1
        app.update
        sleep 0.01
      end

      assert callback_fired, "Widget callback did not fire"
    end
  end

  def test_callback_spawns_thread
    assert_tk_app("Callback should be able to spawn threads") do
      callback_thread_result = nil
      app.command(:button, ".b_thr", command: proc {
        Thread.new { callback_thread_result = "from_callback" }.join
      })
      app.command(:pack, ".b_thr")
      app.command(".b_thr", "invoke")

      start = Time.now
      while Time.now - start < 0.1
        app.update
        sleep 0.01
      end

      assert_equal "from_callback", callback_thread_result, "Thread in callback failed"
    end
  end

  def test_tcl_eval_roundtrip
    assert_tk_app("Tcl eval should return correct result") do
      result = app.tcl_eval("expr {2 + 2}")
      assert_equal "4", result
    end
  end

  def test_tcl_eval_string_roundtrip
    assert_tk_app("Tcl variable round-trip should preserve string") do
      app.set_variable('testvar', 'hello from tcl')
      result = app.get_variable('testvar')
      assert_equal "hello from tcl", result
    end
  end
end
