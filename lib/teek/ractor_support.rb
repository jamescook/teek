# frozen_string_literal: true

# Ractor and background work support for Teek applications.
#
# This module provides a unified API across Ruby versions:
# - Ruby 4.x: Uses Ractor::Port, Ractor.shareable_proc for true parallelism
# - Ruby 3.x: Ractor mode NOT supported (falls back to thread mode)
# - Thread fallback: Always available, works everywhere
#
# The implementation is selected automatically based on Ruby version.

require_relative 'background_thread'

if Ractor.respond_to?(:shareable_proc)
  require_relative 'background_ractor4x'
end

module Teek

  # Unified background work API. Delegates to a mode-specific implementation
  # selected via the +mode:+ parameter.
  #
  # Modes:
  # - +:thread+ — traditional threading; best for I/O-bound work where the GVL
  #   is released during blocking calls. Always available.
  # - +:ractor+ — true parallel execution via Ractor (Ruby 4.x+ only); best
  #   for CPU-bound work.
  #
  # @example Basic usage
  #   task = Teek::BackgroundWork.new(app, data, mode: :thread) do |t, d|
  #     d.each { |item| t.yield(process(item)) }
  #   end
  #   task.on_progress { |r| update_ui(r) }
  #       .on_done { puts "Finished" }
  #
  # @example Pause / resume / stop
  #   task.pause
  #   task.resume
  #   task.stop
  #
  # @example Configuration
  #   Teek::BackgroundWork.poll_ms = 16
  #   Teek::BackgroundWork.drop_intermediate = true
  #   Teek::BackgroundWork.abort_on_error = false
  class BackgroundWork
    class << self
      # @return [Integer] UI poll interval in milliseconds (default 16)
      attr_accessor :poll_ms
      # @return [Boolean] when true, only the latest progress value per poll
      #   cycle is delivered (default true)
      attr_accessor :drop_intermediate
      # @return [Boolean] when true, raise on ractor errors instead of warning
      #   (default false)
      attr_accessor :abort_on_error
    end
    self.poll_ms = 16
    self.drop_intermediate = true
    self.abort_on_error = false

    # @return [Boolean] whether Ractor mode is available (Ruby 4.x+)
    RACTOR_SUPPORTED = Ractor.respond_to?(:shareable_proc)

    # @api private
    @background_modes = {}

    # @api private
    def self.register_background_mode(name, klass)
      @background_modes[name.to_sym] = klass
    end

    # @api private
    def self.background_modes
      @background_modes
    end

    # @api private
    def self.background_mode_class(name)
      @background_modes[name.to_sym]
    end

    # Register built-in modes
    register_background_mode :thread, Teek::BackgroundThread::BackgroundWork

    # Ractor mode only available on Ruby 4.x+
    if RACTOR_SUPPORTED
      register_background_mode :ractor, Teek::BackgroundRactor4x::BackgroundWork
    end

    # @return [String, nil] optional name for this task
    attr_accessor :name

    # @param app [Teek::App] the application instance
    # @param data [Object] data passed to the worker block
    # @param mode [Symbol] +:thread+ or +:ractor+
    # @param worker [Class, nil] optional worker class (must respond to +#call(task, data)+)
    # @yield [task, data] block executed in the background
    # @yieldparam task [BackgroundThread::BackgroundWork::TaskContext, BackgroundRactor4x::BackgroundWork::TaskContext]
    # @yieldparam data [Object]
    # @raise [ArgumentError] if mode is unknown
    def initialize(app, data, mode: :thread, worker: nil, &block)
      impl_class = self.class.background_mode_class(mode)
      unless impl_class
        available = self.class.background_modes.keys.join(', ')
        raise ArgumentError, "Unknown mode: #{mode}. Available: #{available}"
      end

      @impl = impl_class.new(app, data, worker: worker, &block)
      @mode = mode
      @name = nil
    end

    # @return [Symbol] the active mode (+:thread+ or +:ractor+)
    def mode
      @mode
    end

    # @return [Boolean]
    def done?
      @impl.done?
    end

    # @return [Boolean]
    def paused?
      @impl.paused?
    end

    # @yield [value] called on the main thread with each result
    # @return [self]
    def on_progress(&block)
      @impl.on_progress(&block)
      self
    end

    # @yield called on the main thread when the worker completes
    # @return [self]
    def on_done(&block)
      @impl.on_done(&block)
      self
    end

    # @yield [msg] called on the main thread with custom worker messages
    # @return [self]
    def on_message(&block)
      @impl.on_message(&block)
      self
    end

    # Send a message to the worker.
    # @param msg [Object] any value (must be Ractor-shareable in +:ractor+ mode)
    # @return [self]
    def send_message(msg)
      @impl.send_message(msg)
      self
    end

    # Pause the worker.
    # @return [self]
    def pause
      @impl.pause
      self
    end

    # Resume a paused worker.
    # @return [self]
    def resume
      @impl.resume
      self
    end

    # Request the worker to stop.
    # @return [self]
    def stop
      @impl.stop
      self
    end

    # Force-close the worker and associated resources.
    # @return [self]
    def close
      @impl.close if @impl.respond_to?(:close)
      self
    end

    # Explicitly start the worker. Called automatically by {#on_progress}
    # and {#on_done}.
    # @return [self]
    def start
      @impl.start
      self
    end
  end

  # Simplified streaming API without pause/resume support.
  # Uses Ractor on Ruby 4.x+, falls back to threads on 3.x.
  #
  # @example
  #   Teek::RactorStream.new(app, files) do |yielder, data|
  #     data.each { |f| yielder.yield(process(f)) }
  #   end.on_progress { |r| update_ui(r) }
  #      .on_done { puts "Done!" }
  class RactorStream
    def initialize(app, data, &block)
      # Ruby 4.x: use Ractor with shareable_proc for true parallelism
      # Ruby 3.x: use threads (Ractor mode not supported)
      if BackgroundWork::RACTOR_SUPPORTED
        shareable_block = Ractor.shareable_proc(&block)
        wrapped_block = Ractor.shareable_proc do |task, d|
          yielder = StreamYielder.new(task)
          shareable_block.call(yielder, d)
        end
        @impl = Teek::BackgroundRactor4x::BackgroundWork.new(app, data, &wrapped_block)
      else
        wrapped_block = proc do |task, d|
          yielder = StreamYielder.new(task)
          block.call(yielder, d)
        end
        @impl = Teek::BackgroundThread::BackgroundWork.new(app, data, &wrapped_block)
      end
    end

    def on_progress(&block)
      @impl.on_progress(&block)
      self
    end

    def on_done(&block)
      @impl.on_done(&block)
      self
    end

    def cancel
      @impl.stop
    end

    # @api private
    class StreamYielder
      def initialize(task)
        @task = task
      end

      def yield(value)
        @task.yield(value)
      end
    end
  end
end
