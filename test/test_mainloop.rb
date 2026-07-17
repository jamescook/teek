# frozen_string_literal: true

# Tests for Interp#mainloop's thread/interrupt behavior.
#
# These use assert_tk_subprocess (a genuinely fresh process per test),
# not tk_test/assert_tk_app. Teek::TestWorker's persistent Tk app is
# shared across every test in the file and mainloop only returns once
# all windows are destroyed, so calling it there would tear down every
# other test's Tk app. See tk_test_helper.rb's "leave as-is" list.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestMainloop < Minitest::Test
  include TeekTestHelper

  def test_mainloop_runs_and_exits_when_the_window_is_destroyed
    assert_tk_subprocess("mainloop returns once the window is destroyed, default timer") do
      <<~RUBY
        require 'teek'

        app = Teek::App.new
        app.after(200) { app.destroy }
        app.mainloop
      RUBY
    end
  end

  def test_mainloop_blocking_mode_lets_background_threads_run
    assert_tk_subprocess("thread_timer_ms: 0 no longer starves background Ruby threads") do
      <<~RUBY
        require 'teek'

        app = Teek::App.new
        app.interp.thread_timer_ms = 0

        counter = 0
        thread = Thread.new { loop { counter += 1 } }

        app.after(200) { app.destroy }
        app.mainloop
        thread.kill
        thread.join

        raise "background thread starved (counter=\#{counter})" if counter < 1000
      RUBY
    end
  end

  def test_mainloop_blocking_mode_responds_to_a_pending_interrupt_promptly
    assert_tk_subprocess("a blocked mainloop wakes up promptly to deliver a pending interrupt") do
      <<~RUBY
        require 'teek'

        app = Teek::App.new
        app.interp.thread_timer_ms = 0
        # No scheduled events at all - DoOneEvent has nothing to wake it but
        # the interrupt itself, so this proves mainloop_ubf/Tcl_ThreadAlert
        # actually break it out of the blocking wait.

        thread = Thread.new { app.mainloop }
        sleep 0.2 # let mainloop enter its blocking wait

        thread.raise(Interrupt, "simulated Ctrl-C")
        raise "mainloop did not unblock within 5s of the interrupt" unless thread.join(5)
      RUBY
    end
  end
end
