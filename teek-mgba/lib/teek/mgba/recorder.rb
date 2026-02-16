# frozen_string_literal: true

require 'zlib'
require 'thread'

module Teek
  module MGBA
    # Records emulator video + audio to a .trec file.
    #
    # Video is delta-compressed (XOR with previous frame) then zlib level 1.
    # Audio is stored as raw PCM. A background thread handles disk I/O so
    # the frame loop stays fast.
    #
    # @example
    #   recorder = Recorder.new("output.trec", width: 240, height: 160)
    #   recorder.start
    #   loop do
    #     core.run_frame
    #     recorder.capture(core.video_buffer_argb, core.audio_buffer)
    #   end
    #   recorder.stop
    class Recorder
      MAGIC = "TEEKREC\0"
      FOOTER_MAGIC = "TEND"
      VERSION = 1
      FLUSH_INTERVAL = 60 # frames between queue flushes (~1s)

      # @param path [String] output .trec file path
      # @param width [Integer] video width (240 for GBA)
      # @param height [Integer] video height (160 for GBA)
      # @param audio_rate [Integer] audio sample rate (default 44100)
      # @param audio_channels [Integer] audio channels (default 2)
      # @param compression [Integer] zlib compression level 1-9 (default 1 = fastest)
      def initialize(path, width:, height:, audio_rate: 44100, audio_channels: 2,
                     compression: Zlib::BEST_SPEED)
        @path = path
        @width = width
        @height = height
        @audio_rate = audio_rate
        @audio_channels = audio_channels
        @compression = compression
        @frame_size = width * height * 4
        @recording = false
      end

      # Start recording. Writes header and spawns writer thread.
      def start
        raise "Already recording" if @recording
        @recording = true
        @frame_count = 0
        @prev_frame = ("\0" * @frame_size).b
        @batch = []
        @queue = Thread::Queue.new
        @writer = Thread.new { writer_loop }
        @queue.push(build_header)
      end

      # Capture one frame of video + audio.
      # @param video_argb [String] raw ARGB8888 pixel data
      # @param audio_pcm [String] raw s16le stereo PCM data
      def capture(video_argb, audio_pcm)
        return unless @recording

        delta = Teek::MGBA.xor_delta(video_argb, @prev_frame)
        @prev_frame = video_argb.dup

        changed = Teek::MGBA.count_changed_pixels(delta)
        total = @width * @height
        change_pct = total > 0 ? (changed * 100 / total).clamp(0, 100) : 0

        compressed = Zlib::Deflate.deflate(delta, @compression)

        @batch << [change_pct, compressed, audio_pcm || "".b]
        @frame_count += 1

        if @batch.length >= FLUSH_INTERVAL
          flush_batch
        end
      end

      # Stop recording. Flushes remaining data, writes footer, closes file.
      def stop
        return unless @recording
        @recording = false
        flush_batch unless @batch.empty?
        @queue.push(build_footer)
        @queue.push(:done)
        @writer.join
        @writer = nil
        @queue = nil
        @batch = nil
        @prev_frame = nil
      end

      # @return [Boolean] true if currently recording
      def recording?
        @recording
      end

      # @return [Integer] number of frames captured so far
      def frame_count
        @frame_count || 0
      end

      private

      def flush_batch
        data = encode_batch(@batch)
        @queue.push(data)
        @batch = []
      end

      def encode_batch(frames)
        buf = String.new(encoding: Encoding::BINARY, capacity: frames.length * 1024)
        frames.each do |change_pct, compressed_video, audio_pcm|
          buf << [change_pct].pack('C')
          buf << [compressed_video.bytesize].pack('V')
          buf << compressed_video
          buf << [audio_pcm.bytesize].pack('V')
          buf << audio_pcm
        end
        buf
      end

      def build_header
        # 32-byte header
        h = String.new(encoding: Encoding::BINARY, capacity: 32)
        h << MAGIC                              # 8 bytes
        h << [VERSION].pack('C')                # 1 byte
        h << [@width, @height].pack('v2')       # 4 bytes
        h << [262_144, 4389].pack('V2')         # 8 bytes (fps = 262144/4389 ≈ 59.7272)
        h << [@audio_rate].pack('V')            # 4 bytes
        h << [@audio_channels, 16].pack('C2')   # 2 bytes
        h << ("\0" * 5)                         # 5 bytes reserved
        h
      end

      def build_footer
        footer = String.new(encoding: Encoding::BINARY, capacity: 8)
        footer << [@frame_count].pack('V')      # 4 bytes
        footer << FOOTER_MAGIC                  # 4 bytes
        footer
      end

      def writer_loop
        File.open(@path, 'wb') do |f|
          loop do
            chunk = @queue.pop
            break if chunk == :done
            f.write(chunk)
          end
        end
      rescue => e
        warn "teek-mgba: recorder write error: #{e.message}"
      end
    end
  end
end
