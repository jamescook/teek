# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestEvery < Minitest::Test
  include TeekTestHelper

  def test_fires_multiple_times
    assert_tk_app("every should fire repeatedly") do
      count = 0
      app.every(30, on_error: nil) { count += 1 }

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.0
      until count >= 3 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      assert count >= 3, "expected at least 3 ticks, got #{count}"
    end
  end

  def test_cancel_stops_firing
    assert_tk_app("cancel should stop the timer") do
      count = 0
      timer = app.every(30, on_error: nil) { count += 1 }

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
      until count >= 2 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      timer.cancel
      frozen_count = count

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.2
      until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      assert_equal frozen_count, count, "timer kept firing after cancel"
    end
  end

  def test_cancelled_predicate
    assert_tk_app("cancelled? should reflect state") do
      timer = app.every(30, on_error: nil) { }
      refute timer.cancelled?
      timer.cancel
      assert timer.cancelled?
    end
  end

  def test_double_cancel_is_safe
    assert_tk_app("double cancel should not raise") do
      timer = app.every(30, on_error: nil) { }
      timer.cancel
      timer.cancel
      assert timer.cancelled?
    end
  end

  def test_zero_interval_raises
    assert_tk_app("zero interval should raise ArgumentError") do
      assert_raises(ArgumentError) { app.every(0, on_error: nil) { } }
    end
  end

  def test_negative_interval_raises
    assert_tk_app("negative interval should raise ArgumentError") do
      assert_raises(ArgumentError) { app.every(-10, on_error: nil) { } }
    end
  end

  # -- on_error: :raise (default) ---------------------------------------------

  def test_raise_default_cancels_on_error
    assert_tk_app("on_error: :raise should cancel timer") do
      count = 0
      timer = app.every(30) do
        count += 1
        raise "boom" if count == 2
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
      until timer.cancelled? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      assert timer.cancelled?, "timer should be cancelled after error"
      assert_equal 2, count, "should have ticked twice before error"
      refute_nil timer.last_error
      assert_equal "boom", timer.last_error.message
    end
  end

  def test_raise_default_does_not_hang
    assert_tk_app("on_error: :raise should not hang the event loop") do
      count = 0
      timer = app.every(30) do
        count += 1
        raise "fail" if count == 1
      end

      # Pump events — should not hang
      20.times { app.update; sleep 0.01 }

      assert timer.cancelled?
      assert_equal 1, count
    end
  end

  # -- on_error: proc ---------------------------------------------------------

  def test_proc_handler_keeps_timer_alive
    assert_tk_app("on_error proc should keep timer running") do
      errors = []
      count = 0

      app.every(30, on_error: ->(e) { errors << e.message }) do
        count += 1
        raise "oops" if count == 2
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
      until count >= 4 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      assert count >= 4, "expected at least 4 ticks, got #{count}"
      assert_equal ["oops"], errors
    end
  end

  def test_proc_handler_receives_exception
    assert_tk_app("on_error proc should receive the exception object") do
      captured = nil
      timer = app.every(30, on_error: ->(e) { captured = e }) do
        raise ArgumentError, "bad arg"
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.5
      until captured || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      timer.cancel
      assert_kind_of ArgumentError, captured
      assert_equal "bad arg", captured.message
    end
  end

  def test_proc_handler_that_raises_cancels_timer
    assert_tk_app("on_error proc that raises should cancel the timer") do
      count = 0
      timer = app.every(30, on_error: ->(_e) { raise "handler boom" }) do
        count += 1
        raise "tick boom" if count == 2
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
      until timer.cancelled? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      assert timer.cancelled?, "timer should be cancelled when on_error raises"
      assert_equal 2, count
      assert_equal "handler boom", timer.last_error.message
    end
  end

  # -- on_error: nil -----------------------------------------------------------

  def test_nil_silently_cancels
    assert_tk_app("on_error: nil should silently cancel") do
      count = 0
      timer = app.every(30, on_error: nil) do
        count += 1
        raise "quiet" if count == 2
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.5
      until timer.cancelled? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      assert timer.cancelled?
      assert_equal 2, count
      refute_nil timer.last_error
      assert_equal "quiet", timer.last_error.message
    end
  end

  def test_nil_does_not_spam_after_error
    assert_tk_app("on_error: nil should not keep firing after error") do
      count = 0
      timer = app.every(30, on_error: nil) do
        count += 1
        raise "stop" if count == 1
      end

      20.times { app.update; sleep 0.01 }

      assert_equal 1, count, "timer should have stopped after first error"
      assert timer.cancelled?
    end
  end

  # -- interval ----------------------------------------------------------------

  def test_interval_accessor
    assert_tk_app("interval should be readable and writable") do
      timer = app.every(30, on_error: nil) { }
      assert_equal 30, timer.interval
      timer.interval = 100
      assert_equal 100, timer.interval
      timer.cancel
    end
  end

  def test_interval_rejects_non_positive
    assert_tk_app("interval= should reject non-positive") do
      timer = app.every(30, on_error: nil) { }
      assert_raises(ArgumentError) { timer.interval = 0 }
      assert_raises(ArgumentError) { timer.interval = -5 }
      timer.cancel
    end
  end

  # -- introspection -----------------------------------------------------------

  def test_late_ticks_starts_at_zero
    assert_tk_app("late_ticks should start at zero") do
      timer = app.every(30, on_error: nil) { }
      assert_equal 0, timer.late_ticks
      timer.cancel
    end
  end

  def test_last_error_nil_when_no_errors
    assert_tk_app("last_error should be nil when no errors") do
      timer = app.every(30, on_error: nil) { }
      assert_nil timer.last_error
      timer.cancel
    end
  end
end
