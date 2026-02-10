# frozen_string_literal: true

# Tests for Teek::BackgroundWork and Teek::RactorStream
#
# Note: Ractor mode requires Ruby 4.x+ (Ractor.shareable_proc).
# On Ruby 3.x, only thread mode is available.
# Ractor tests are skipped on Ruby 3.x.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestBackgroundWork < Minitest::Test
  include TeekTestHelper

  def test_background_work_thread_basic
    assert_tk_app("background_work :thread mode should work") do
      Teek::BackgroundWork.drop_intermediate = false

      results = []
      done = false

      Teek::BackgroundWork.new(app, [1, 2, 3], mode: :thread) do |t, data|
        data.each { |n| t.yield(n * 10) }
      end.on_progress do |result|
        results << result
      end.on_done do
        done = true
      end

      start = Time.now
      while !done && (Time.now - start) < 5
        app.update
        sleep 0.01
      end

      Teek::BackgroundWork.drop_intermediate = true

      assert done, "Thread task did not complete"
      assert_equal [10, 20, 30], results
    end
  end

  def test_background_work_thread_pause
    assert_tk_app("background_work :thread pause should work") do
      counter = 0
      done = false

      task = Teek::BackgroundWork.new(app, 50, mode: :thread) do |t, count|
        count.times do |i|
          t.check_pause
          t.yield(i)
          sleep 0.02
        end
      end.on_progress do |i|
        counter = i
      end.on_done do
        done = true
      end

      start = Time.now
      while counter < 10 && (Time.now - start) < 2
        app.update
        sleep 0.01
      end

      task.pause
      paused_at = counter

      sleep 0.2
      10.times { app.update; sleep 0.02 }
      after_pause = counter

      advance = after_pause - paused_at
      assert_operator advance, :<=, 3, "Counter advanced too much while paused: #{advance}"

      task.resume

      start = Time.now
      while !done && (Time.now - start) < 5
        app.update
        sleep 0.01
      end

      assert done, "Task did not complete after resume"
      assert_equal 49, counter
    end
  end

  def test_background_work_ractor_basic
    skip "Ractor mode requires Ruby 4.x+" unless Ractor.respond_to?(:shareable_proc)
    assert_tk_app("background_work :ractor mode should work", pipe_capture: true) do
      Teek::BackgroundWork.drop_intermediate = false

      results = []
      done = false

      Teek::BackgroundWork.new(app, [1, 2, 3], mode: :ractor) do |t, data|
        data.each { |n| t.yield(n * 10) }
      end.on_progress do |result|
        results << result
      end.on_done do
        done = true
      end

      start = Time.now
      while !done && (Time.now - start) < 5
        app.update
        sleep 0.01
      end

      Teek::BackgroundWork.drop_intermediate = true

      assert done, "Ractor task did not complete"
      assert_equal [10, 20, 30], results
    end
  end

  def test_background_work_ractor_messaging
    skip "Ractor mode requires Ruby 4.x+" unless Ractor.respond_to?(:shareable_proc)
    assert_tk_app("ractor messaging works", pipe_capture: true) do
      Teek::BackgroundWork.drop_intermediate = false
      received_by_main = []
      done = false

      task = Teek::BackgroundWork.new(app, nil, mode: :ractor) do |t, _|
        msg = t.wait_message
        t.send_message("echo:#{msg}")
        t.yield(:done)
      end

      task.on_message { |msg| received_by_main << msg }
      task.on_progress { |_| }
      task.on_done { done = true }
      task.send_message("hello")

      wait_until(timeout: 5.0) { done }
      Teek::BackgroundWork.drop_intermediate = true

      assert done, "Ractor task should complete"
      assert_includes received_by_main, "echo:hello"
    end
  end

  def test_background_work_ractor_pause
    skip "Ractor mode requires Ruby 4.x+" unless Ractor.respond_to?(:shareable_proc)
    assert_tk_app("ractor pause/resume works", pipe_capture: true) do
      counter = 0
      done = false

      task = Teek::BackgroundWork.new(app, 50, mode: :ractor) do |t, count|
        count.times do |i|
          t.check_pause
          t.yield(i)
          sleep 0.02
        end
      end.on_progress { |i| counter = i }
        .on_done { done = true }

      wait_until(timeout: 2.0) { counter >= 5 }
      task.pause
      assert task.paused?

      sleep 0.2
      5.times { app.update; sleep 0.02 }

      task.resume
      refute task.paused?

      wait_until(timeout: 5.0) { done }
      assert done, "Ractor task should complete after resume"
    end
  end

  def test_background_work_ractor_stop
    skip "Ractor mode requires Ruby 4.x+" unless Ractor.respond_to?(:shareable_proc)
    assert_tk_app("ractor stop works", pipe_capture: true) do
      progress_count = 0
      done = false

      task = Teek::BackgroundWork.new(app, 1000, mode: :ractor) do |t, count|
        count.times do |i|
          t.check_message
          t.yield(i)
          sleep 0.01
        end
      end.on_progress { |_| progress_count += 1 }
        .on_done { done = true }

      wait_until { progress_count >= 3 }
      task.stop

      wait_until(timeout: 5.0) { done }
      assert done, "Ractor task should complete after stop"
      assert task.done?
    end
  end

  def test_background_work_ractor_close
    skip "Ractor mode requires Ruby 4.x+" unless Ractor.respond_to?(:shareable_proc)
    assert_tk_app("ractor close works", pipe_capture: true) do
      task = Teek::BackgroundWork.new(app, nil, mode: :ractor) do |t, _|
        loop { sleep 0.1 }
      end.on_progress { |_| }

      task.start
      sleep 0.1
      app.update

      task.close
      assert task.done?
    end
  end

  def test_background_work_thread_final_progress
    assert_tk_app("background_work :thread should receive final progress") do
      progress_values = []
      final_progress_before_done = nil
      done = false

      Teek::BackgroundWork.new(app, { total: 5 }, mode: :thread) do |t, data|
        data[:total].times do |i|
          t.yield((i + 1).to_f / data[:total])
        end
      end.on_progress do |progress|
        progress_values << progress
      end.on_done do
        final_progress_before_done = progress_values.last
        done = true
      end

      start = Time.now
      while !done && (Time.now - start) < 5
        app.update
        sleep 0.01
      end

      assert done, "Task did not complete"
      assert_equal 1.0, final_progress_before_done, "Expected final progress 1.0 before done"
      assert_includes progress_values, 1.0
    end
  end

  def test_ractor_stream_basic
    assert_tk_app("RactorStream should yield values to callback") do
      Teek::BackgroundWork.drop_intermediate = false

      results = []
      done = false

      Teek::RactorStream.new(app, [1, 2, 3]) do |yielder, data|
        data.each { |n| yielder.yield(n * 10) }
      end.on_progress do |result|
        results << result
      end.on_done do
        done = true
      end

      start = Time.now
      while !done && (Time.now - start) < 5
        app.update
        sleep 0.01
      end

      Teek::BackgroundWork.drop_intermediate = true

      assert done, "Stream did not complete"
      assert_equal [10, 20, 30], results
    end
  end

  def test_background_work_mode
    assert_tk_app("mode returns the active mode") do
      done = false
      task = Teek::BackgroundWork.new(app, nil, mode: :thread) do |t, _|
        t.yield(:ok)
      end.on_progress { |_| }.on_done { done = true }

      wait_until { done }
      assert_equal :thread, task.mode
    end
  end

  def test_background_work_done_and_paused
    assert_tk_app("done? and paused? reflect state") do
      task = Teek::BackgroundWork.new(app, nil, mode: :thread) do |t, _|
        t.check_pause
        t.yield(:ok)
      end

      refute task.done?
      refute task.paused?

      done = false
      task.on_progress { |_| }.on_done { done = true }
      wait_until { done }

      assert task.done?
    end
  end

  def test_background_work_messaging
    assert_tk_app("on_message and send_message work bidirectionally") do
      Teek::BackgroundWork.drop_intermediate = false
      received_by_main = []
      done = false

      task = Teek::BackgroundWork.new(app, nil, mode: :thread) do |t, _|
        # Worker waits for a message from main
        msg = t.wait_message
        # Worker sends a message back
        t.send_message("echo:#{msg}")
        t.yield(:done)
      end

      task.on_message { |msg| received_by_main << msg }
      task.on_progress { |_| }
      task.on_done { done = true }

      # Send message to worker
      task.send_message("hello")

      wait_until(timeout: 3.0) { done }
      Teek::BackgroundWork.drop_intermediate = true

      assert done, "Task should complete"
      assert_includes received_by_main, "echo:hello"
    end
  end

  def test_background_work_check_message
    assert_tk_app("TaskContext check_message returns nil when empty") do
      Teek::BackgroundWork.drop_intermediate = false
      results = []
      done = false

      Teek::BackgroundWork.new(app, nil, mode: :thread) do |t, _|
        # check_message should return nil when no messages
        msg = t.check_message
        t.yield(msg.nil? ? "none" : msg.to_s)
      end.on_progress { |r| results << r }
        .on_done { done = true }

      wait_until(timeout: 3.0) { done }
      Teek::BackgroundWork.drop_intermediate = true

      assert_equal ["none"], results
    end
  end

  def test_background_work_stop
    assert_tk_app("stop terminates the worker") do
      progress_count = 0
      done = false

      task = Teek::BackgroundWork.new(app, 1000, mode: :thread) do |t, count|
        count.times do |i|
          t.check_message
          t.yield(i)
          sleep 0.01
        end
      end.on_progress { |_| progress_count += 1 }
        .on_done { done = true }

      # Let it run a bit then stop
      wait_until { progress_count >= 3 }
      task.stop

      wait_until(timeout: 3.0) { done }
      assert done, "Task should complete after stop"
      assert_operator progress_count, :<, 1000, "Should not have run all iterations"
    end
  end

  def test_background_work_close
    assert_tk_app("close force-kills the worker") do
      task = Teek::BackgroundWork.new(app, nil, mode: :thread) do |t, _|
        loop { sleep 0.1 }
      end.on_progress { |_| }

      task.start
      refute task.done?

      task.close
      assert task.done?
    end
  end

  def test_background_work_background_modes
    assert_tk_app("background_modes lists registered modes") do
      modes = Teek::BackgroundWork.background_modes
      assert modes.key?(:thread), "thread mode should be registered"
    end
  end

  def test_ractor_stream_error_handling
    assert_tk_app("RactorStream should handle errors in work block") do
      done = false

      original_warn = $stderr
      captured = StringIO.new
      $stderr = captured

      Teek::RactorStream.new(app, :unused) do |yielder, _data|
        raise "Intentional test error"
      end.on_done do
        done = true
      end

      start = Time.now
      while !done && (Time.now - start) < 5
        app.update
        sleep 0.01
      end

      $stderr = original_warn
      warning_output = captured.string

      assert done, "Task should complete even with error"
      assert_includes warning_output, "Intentional test error"
    end
  end
end
