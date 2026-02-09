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
