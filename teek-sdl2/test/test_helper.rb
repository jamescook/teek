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
