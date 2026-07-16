# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  require_relative '../../test/simplecov_config'

  coverage_name = ENV['COVERAGE_NAME'] || 'sdl2'
  SimpleCov.coverage_dir "#{SimpleCovConfig::PROJECT_ROOT}/coverage/results/#{coverage_name}"
  SimpleCov.command_name "sdl2:#{coverage_name}"
  SimpleCov.print_error_status = false
  SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter

  SimpleCov.start do
    SimpleCovConfig.apply_filters(self)
    track_files "#{SimpleCovConfig::PROJECT_ROOT}/lib/**/*.rb"
  end
end

require "minitest/autorun"

module TeekSDL2TestHelper
  # Halt every mixer channel before any per-test teardown gets a chance
  # to free a Mix_Chunk or close the mixer. SDL_mixer forbids freeing a
  # chunk that's still playing (the mixing thread runs even under the
  # dummy audio driver, so this is a real use-after-free, not a
  # theoretical one) - a single test that fails before reaching its own
  # cleanup leaves a channel looping forever, and the next test's
  # teardown frees a chunk out from under it, corrupting SDL_mixer's own
  # internal channel state for every test that runs afterward. Chained
  # via +super+ (Minitest's own +before_teardown+/+teardown+/
  # +after_teardown+ lifecycle, distinct from plain method overriding),
  # and guarded by {Teek::SDL2.audio_open?} so this is a clean no-op for
  # any test that never opened audio in the first place.
  def before_teardown
    super
    Teek::SDL2.halt(-1) if Teek::SDL2.audio_open?
  end

  # Poll +timeout+ seconds for the block to return truthy, instead of a
  # single check right after an operation that takes effect asynchronously
  # (e.g. pause/resume state on SDL_mixer's own audio thread) - a fixed
  # `sleep` before that check is exactly the flaky pattern this replaces,
  # since it assumes a fixed duration is always enough regardless of how
  # loaded the machine running it is.
  # @return the block's last (truthy or falsy) result
  def wait_until(timeout: 1.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    result = nil
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      result = yield
      break if result
      sleep 0.02
    end
    result
  end
end
