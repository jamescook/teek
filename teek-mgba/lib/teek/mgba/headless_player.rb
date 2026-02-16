# frozen_string_literal: true

require 'fileutils'
require 'zlib'

module Teek
  module MGBA
    # Headless mGBA player for scripting and automated testing.
    # Wraps Core with a simple API — no Tk, no SDL2, no event loop.
    #
    # @example Run 60 frames and inspect the video buffer
    #   HeadlessPlayer.open("game.gba") do |player|
    #     player.step(60)
    #     pixels = player.video_buffer_argb  # 240*160*4 bytes
    #   end
    class HeadlessPlayer
      # @param rom_path [String] path to ROM file (.gba, .gb, .gbc, .zip)
      # @param config [Config, nil] config object (uses default if nil)
      def initialize(rom_path, config: nil)
        @config = config || Teek::MGBA.user_config
        rom_path = RomLoader.resolve(rom_path)

        saves = @config.saves_dir
        FileUtils.mkdir_p(saves) unless File.directory?(saves)
        @core = Core.new(rom_path, saves)
        @keys = 0
      end

      # Open a HeadlessPlayer, yield it, and close when done.
      # @param rom_path [String]
      # @param opts [Hash] passed to {#initialize}
      # @yield [HeadlessPlayer]
      # @return result of block
      def self.open(rom_path, **opts)
        player = new(rom_path, **opts)
        begin
          yield player
        ensure
          player.close
        end
      end

      # Run one or more frames. Captures to recorder if recording.
      # @param n [Integer] number of frames to advance (default 1)
      # @yield [Integer] frame number (1-based) after each frame, if block given
      def step(n = 1)
        check_open!
        if block_given?
          n.times do |i|
            @core.run_frame
            @recorder&.capture(@core.video_buffer_argb, @core.audio_buffer) if @recorder&.recording?
            yield i + 1
          end
        else
          n.times do
            @core.run_frame
            @recorder&.capture(@core.video_buffer_argb, @core.audio_buffer) if @recorder&.recording?
          end
        end
      end

      # Set currently pressed buttons as a bitmask.
      # Use KEY_* constants: `player.press(KEY_A | KEY_START)`
      # @param keys [Integer] bitwise OR of KEY_* constants
      def press(keys)
        check_open!
        @keys = keys
        @core.set_keys(@keys)
      end

      # Release all buttons.
      def release_all
        check_open!
        @keys = 0
        @core.set_keys(0)
      end

      # @return [String] raw ARGB8888 pixel data (240*160*4 bytes for GBA)
      def video_buffer_argb
        check_open!
        @core.video_buffer_argb
      end

      # @return [String] raw interleaved stereo PCM audio data
      def audio_buffer
        check_open!
        @core.audio_buffer
      end

      # @return [Integer] video width in pixels
      def width
        check_open!
        @core.width
      end

      # @return [Integer] video height in pixels
      def height
        check_open!
        @core.height
      end

      # @!group ROM metadata

      def title;      check_open!; @core.title;      end
      def game_code;  check_open!; @core.game_code;  end
      def maker_code; check_open!; @core.maker_code; end
      def checksum;   check_open!; @core.checksum;   end
      def platform;   check_open!; @core.platform;   end
      def rom_size;   check_open!; @core.rom_size;   end

      # @!endgroup

      # @!group Save states

      # @param path [String] destination file path
      # @return [Boolean] true on success
      def save_state(path)
        check_open!
        @core.save_state_to_file(path)
      end

      # @param path [String] state file path
      # @return [Boolean] true on success
      def load_state(path)
        check_open!
        @core.load_state_from_file(path)
      end

      # @!endgroup

      # @!group Rewind

      def rewind_init(seconds)
        check_open!
        @core.rewind_init(seconds)
      end

      def rewind_push
        check_open!
        @core.rewind_push
      end

      # @return [Boolean] true if a snapshot was loaded
      def rewind_pop
        check_open!
        @core.rewind_pop
      end

      # @return [Integer] number of saved snapshots
      def rewind_count
        check_open!
        @core.rewind_count
      end

      def rewind_deinit
        check_open!
        @core.rewind_deinit
      end

      # @!endgroup

      # @!group Recording

      # Start recording video + audio to a .trec file.
      # @param path [String] output file path
      # @param compression [Integer] zlib level 1-9 (default 1 = fastest)
      def start_recording(path, compression: Zlib::BEST_SPEED)
        check_open!
        raise "Already recording" if recording?
        @recorder = Recorder.new(path, width: @core.width, height: @core.height,
                                 compression: compression)
        @recorder.start
      end

      # Stop recording and finalize the file.
      def stop_recording
        @recorder&.stop
        @recorder = nil
      end

      # @return [Boolean] true if currently recording
      def recording?
        @recorder&.recording? || false
      end

      # @!endgroup

      # Shut down the core and free resources.
      def close
        return if closed?
        stop_recording if recording?
        @core.destroy
        @core = nil
      end

      # @return [Boolean] true if the player has been closed
      def closed?
        @core.nil? || @core.destroyed?
      end

      private

      def check_open!
        raise "HeadlessPlayer is closed" if closed?
      end
    end
  end
end
