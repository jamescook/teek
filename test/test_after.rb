# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestAfter < Minitest::Test
  include TeekTestHelper

  def test_after_fires
    assert_tk_app("after should fire callback") do
      fired = false
      app.after(50) { fired = true }

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.0
      until fired || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      assert fired, "timer did not fire"
    end
  end

  def test_after_idle_fires
    assert_tk_app("after_idle should fire callback") do
      fired = false
      app.after_idle { fired = true }

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.0
      until fired || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      assert fired, "after_idle did not fire"
    end
  end

  def test_after_cancel
    assert_tk_app("after_cancel should prevent callback") do
      fired = false
      timer_id = app.after(50) { fired = true }
      app.after_cancel(timer_id)

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
      until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      refute fired, "callback fired despite cancel"
    end
  end

  def test_nested_after
    assert_tk_app("nested timers should both fire") do
      results = []

      app.after(50) do
        results << "first"
        app.after(50) do
          results << "second"
        end
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.0
      until results.size >= 2 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        app.update
        sleep 0.01
      end

      assert_equal ["first", "second"], results
    end
  end
end
