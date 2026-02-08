# frozen_string_literal: true

module Teek
  # Synchronous "background" work - runs on main thread, blocks UI.
  #
  # FOR TESTING AND DEMONSTRATION ONLY.
  #
  # This mode exists to show what happens WITHOUT background processing:
  # the UI freezes during work. Use it in demos to contrast with :thread
  # and :ractor modes which keep the UI responsive.
  #
  # Not registered by default. To use:
  #   require 'teek/background_none'
  #   Teek::BackgroundWork.register_background_mode :none, Teek::BackgroundNone::BackgroundWork
  #
  # @api private
  module BackgroundNone
    class BackgroundWork
      def initialize(app, data, worker: nil, &block)
        @app = app
        @data = data
        @work_block = block || (worker && proc { |t, d| worker.new.call(t, d) })
        @callbacks = { progress: nil, done: nil, message: nil }
        @message_queue = []
        @started = false
        @done = false
        @paused = false
      end

      def on_progress(&block)
        @callbacks[:progress] = block
        maybe_start
        self
      end

      def on_done(&block)
        @callbacks[:done] = block
        maybe_start
        self
      end

      def on_message(&block)
        @callbacks[:message] = block
        self
      end

      def send_message(msg)
        @message_queue << msg
        self
      end

      def pause
        @paused = true
        send_message(:pause)
        self
      end

      def resume
        @paused = false
        send_message(:resume)
        self
      end

      def stop
        send_message(:stop)
        self
      end

      def close
        self
      end

      def done?
        @done
      end

      def paused?
        @paused
      end

      def start
        maybe_start
        self
      end

      private

      def maybe_start
        return if @started
        @started = true
        @app.after(0) { do_work }
      end

      def do_work
        task = TaskContext.new(@app, @callbacks, @message_queue)
        begin
          @work_block.call(task, @data)
        rescue StopIteration
          # Worker requested stop
        rescue => e
          warn "[None] Background work error: #{e.class}: #{e.message}"
        end

        @done = true
        @callbacks[:done]&.call
      end

      # Synchronous task context - callbacks fire immediately
      class TaskContext
        def initialize(app, callbacks, message_queue)
          @app = app
          @callbacks = callbacks
          @message_queue = message_queue
          @paused = false
        end

        def yield(value)
          @callbacks[:progress]&.call(value)
        end

        def check_message
          msg = @message_queue.shift
          handle_control_message(msg) if msg
          msg
        end

        def wait_message
          check_message
        end

        def send_message(msg)
          @callbacks[:message]&.call(msg)
        end

        def check_pause
          while @paused
            @app.update
            msg = check_message
            break unless @paused
          end
        end

        private

        def handle_control_message(msg)
          case msg
          when :pause
            @paused = true
          when :resume
            @paused = false
          when :stop
            raise StopIteration
          end
        end
      end
    end
  end
end
