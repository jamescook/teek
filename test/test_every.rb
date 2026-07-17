# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestEvery < Minitest::Test
  include TeekTestHelper

  tk_test "every should fire repeatedly" do
    count = 0
    app.every(30, on_error: nil) { count += 1 }

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.0
    until count >= 3 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      app.update
      sleep 0.01
    end

    assert count >= 3, "expected at least 3 ticks, got #{count}"
  end

  tk_test "cancel should stop the timer" do
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

  tk_test "cancelled? should reflect state" do
    timer = app.every(30, on_error: nil) { }
    refute timer.cancelled?
    timer.cancel
    assert timer.cancelled?
  end

  tk_test "double cancel should not raise" do
    timer = app.every(30, on_error: nil) { }
    timer.cancel
    timer.cancel
    assert timer.cancelled?
  end

  tk_test "zero interval should raise ArgumentError" do
    assert_raises(ArgumentError) { app.every(0, on_error: nil) { } }
  end

  tk_test "negative interval should raise ArgumentError" do
    assert_raises(ArgumentError) { app.every(-10, on_error: nil) { } }
  end

  # -- on_error: :raise (default) ---------------------------------------------

  tk_test "on_error: :raise should raise from app.update" do
    count = 0
    timer = app.every(30) do
      count += 1
      raise "boom" if count == 2
    end

    caught = nil
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
    until caught || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      begin
        app.update
      rescue RuntimeError => e
        caught = e
      end
      sleep 0.01
    end

    assert timer.cancelled?, "timer should be cancelled after error"
    assert_equal 2, count, "should have ticked twice before error"
    refute_nil caught, "exception should propagate from app.update"
    assert_equal "boom", caught.message
    assert_equal "boom", timer.last_error.message
  end

  tk_test "on_error: :raise should not hang the event loop" do
    count = 0
    timer = app.every(30) do
      count += 1
      raise "fail" if count == 1
    end

    caught = nil
    20.times do
      begin
        app.update
      rescue RuntimeError => e
        caught = e
      end
      sleep 0.01
    end

    assert timer.cancelled?
    assert_equal 1, count
    refute_nil caught
    assert_equal "fail", caught.message
  end

  tk_test "on_error: :raise should not spam exceptions" do
    count = 0
    app.every(30) do
      count += 1
      raise "once" if count == 1
    end

    errors = []
    30.times do
      begin
        app.update
      rescue RuntimeError => e
        errors << e.message
      end
      sleep 0.01
    end

    assert_equal ["once"], errors, "should raise exactly once, not spam"
  end

  # -- on_error: proc ---------------------------------------------------------

  tk_test "on_error proc should keep timer running" do
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

  tk_test "on_error proc should receive the exception object" do
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

  tk_test "on_error proc that raises should cancel the timer" do
    count = 0
    timer = app.every(30, on_error: ->(_e) { raise "handler boom" }) do
      count += 1
      raise "tick boom" if count == 2
    end

    caught = nil
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
    until timer.cancelled? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      begin
        app.update
      rescue RuntimeError => e
        caught = e
      end
      sleep 0.01
    end

    assert timer.cancelled?, "timer should be cancelled when on_error raises"
    assert_equal 2, count
    assert_equal "handler boom", timer.last_error.message
    refute_nil caught, "handler error should raise from app.update"
    assert_equal "handler boom", caught.message
  end

  # -- on_error: nil -----------------------------------------------------------

  tk_test "on_error: nil should silently cancel" do
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

  tk_test "on_error: nil should not keep firing after error" do
    count = 0
    timer = app.every(30, on_error: nil) do
      count += 1
      raise "stop" if count == 1
    end

    20.times { app.update; sleep 0.01 }

    assert_equal 1, count, "timer should have stopped after first error"
    assert timer.cancelled?
  end

  # -- interval ----------------------------------------------------------------

  tk_test "interval should be readable and writable" do
    timer = app.every(30, on_error: nil) { }
    assert_equal 30, timer.interval
    timer.interval = 100
    assert_equal 100, timer.interval
    timer.cancel
  end

  tk_test "interval= should reject non-positive" do
    timer = app.every(30, on_error: nil) { }
    assert_raises(ArgumentError) { timer.interval = 0 }
    assert_raises(ArgumentError) { timer.interval = -5 }
    timer.cancel
  end

  # -- introspection -----------------------------------------------------------

  tk_test "late_ticks should start at zero" do
    timer = app.every(30, on_error: nil) { }
    assert_equal 0, timer.late_ticks
    timer.cancel
  end

  tk_test "last_error should be nil when no errors" do
    timer = app.every(30, on_error: nil) { }
    assert_nil timer.last_error
    timer.cancel
  end
end
