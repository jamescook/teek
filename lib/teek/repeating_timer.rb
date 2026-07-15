# frozen_string_literal: true

module Teek
  # A cancellable repeating timer that fires on the main thread.
  #
  # Created via {App#every}. Reschedules itself after each tick using
  # Tcl's +after+ command. The block runs in the event loop, so it
  # must complete quickly to avoid blocking the UI.
  #
  # Tracks timing drift: if a tick fires significantly late (more than
  # 2x the interval), a warning is printed to stderr. This helps catch
  # blocks that are too slow for the requested interval.
  #
  # @see App#every
  class RepeatingTimer
    # @return [Integer] interval in milliseconds
    attr_reader :interval

    # @return [Exception, nil] the last error if the timer stopped due to an
    #   unhandled exception, nil otherwise
    attr_reader :last_error

    # @return [Integer] number of ticks that fired late (> 2x interval)
    attr_reader :late_ticks

    # @api private
    def initialize(app, ms, on_error: nil, &block)
      raise ArgumentError, "interval must be positive, got #{ms}" if ms <= 0

      @app = app
      @interval = ms
      @block = block
      @on_error = on_error
      @cancelled = false
      @after_id = nil
      @last_error = nil
      @late_ticks = 0
      @next_expected = nil
      schedule
    end

    # Stop the timer. Safe to call multiple times.
    # @return [void]
    def cancel
      return if @cancelled
      @cancelled = true
      @app.after_cancel(@after_id) if @after_id
      @after_id = nil
    end

    # @return [Boolean] true if the timer has been cancelled
    def cancelled?
      @cancelled
    end

    # Change the interval. Takes effect on the next tick.
    # @param ms [Integer] new interval in milliseconds
    def interval=(ms)
      raise ArgumentError, "interval must be positive, got #{ms}" if ms <= 0
      @interval = ms
    end

    private

    def schedule
      return if @cancelled
      @next_expected = now_ms + @interval
      @after_id = @app.after(@interval) { tick }
    end

    def tick
      return if @cancelled
      check_drift
      @block.call
      schedule
    rescue => e
      @last_error = e
      case @on_error
      when :raise
        @cancelled = true
        # Store on App so it raises from the next app.update call.
        # Don't re-raise here — that would go through rb_protect → bgerror.
        @app._pending_exception = e
      when Proc
        begin
          @on_error.call(e)
        rescue => handler_err
          @last_error = handler_err
          @cancelled = true
          @app._pending_exception = handler_err
          return
        end
        schedule
      when nil
        @cancelled = true
      end
    end

    def check_drift
      return unless @next_expected
      actual = now_ms
      drift = actual - @next_expected
      if drift > @interval
        @late_ticks += 1
        warn "Teek::RepeatingTimer: tick #{@late_ticks} fired #{drift.round}ms late " \
             "(interval=#{@interval}ms)"
      end
    end

    def now_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    end
  end
end
