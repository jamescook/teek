# frozen_string_literal: true

require 'fileutils'
require_relative 'locale'

module Teek
  module MGBA
    # Manages save state persistence: save, load, screenshot capture,
    # debounce, and backup rotation.
    #
    # All dependencies are injected via the constructor so the class can be
    # tested with lightweight mocks (no real mGBA Core or Tk interpreter).
    #
    # @example Production usage (inside Player)
    #   @save_mgr = SaveStateManager.new(core: @core, config: @config, app: @app)
    #   success, msg = @save_mgr.save_state(1)
    #   show_toast(msg)
    #
    # @example Test usage (with mocks)
    #   mgr = SaveStateManager.new(core: mock_core, config: config, app: mock_app)
    #   success, msg = mgr.save_state(1)
    #   assert success
    class SaveStateManager
      include Locale::Translatable

      GBA_W = 240
      GBA_H = 160

      def initialize(core:, config:, app:)
        @core = core
        @config = config
        @app = app
        @last_save_time = 0
        @state_dir = nil
        @quick_save_slot = config.quick_save_slot
        @backup = config.save_state_backup?
      end

      # @return [Integer] quick save/load slot
      attr_accessor :quick_save_slot

      # @return [Boolean] whether to create .bak files
      attr_accessor :backup

      # @return [Core] the mGBA core (swappable for reset/ROM change)
      attr_accessor :core

      # Build per-ROM state directory path using game code + CRC32.
      # e.g. states/AGB-BTKE-A1B2C3D4/
      # @param core [Core, #game_code, #checksum] the emulator core
      # @return [String] directory path
      def state_dir_for_rom(core)
        code = core.game_code.gsub(/[^a-zA-Z0-9_.-]/, '_')
        crc  = format('%08X', core.checksum)
        File.join(@config.states_dir, "#{code}-#{crc}")
      end

      # Set the state directory (called after ROM load).
      # @param dir [String]
      attr_writer :state_dir

      # @return [String, nil] current state directory
      attr_reader :state_dir

      # @param slot [Integer]
      # @return [String] path to the save state file for this slot
      def state_path(slot)
        File.join(@state_dir, "state#{slot}.ss")
      end

      # @param slot [Integer]
      # @return [String] path to the screenshot PNG for this slot
      def screenshot_path(slot)
        File.join(@state_dir, "state#{slot}.png")
      end

      # Save the emulator state to the given slot.
      # @param slot [Integer]
      # @return [Array(Boolean, String)] success flag and translated message
      def save_state(slot)
        return [false, nil] unless @core && !@core.destroyed?

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if now - @last_save_time < @config.save_state_debounce
          return [false, translate('toast.save_blocked')]
        end

        FileUtils.mkdir_p(@state_dir) unless File.directory?(@state_dir)

        # Backup rotation: rename existing files → .bak
        ss = state_path(slot)
        png = screenshot_path(slot)
        if @backup
          File.rename(ss, "#{ss}.bak") if File.exist?(ss)
          File.rename(png, "#{png}.bak") if File.exist?(png)
        end

        if @core.save_state_to_file(ss)
          @last_save_time = now
          save_screenshot(png)
          [true, translate('toast.state_saved', slot: slot)]
        else
          [false, translate('toast.save_failed')]
        end
      end

      # Load the emulator state from the given slot.
      # @param slot [Integer]
      # @return [Array(Boolean, String)] success flag and translated message
      def load_state(slot)
        return [false, nil] unless @core && !@core.destroyed?

        ss = state_path(slot)
        unless File.exist?(ss)
          return [false, translate('toast.no_state', slot: slot)]
        end

        if @core.load_state_from_file(ss)
          [true, translate('toast.state_loaded', slot: slot)]
        else
          [false, translate('toast.load_failed')]
        end
      end

      # Save to the quick save slot.
      # @return [Array(Boolean, String)]
      def quick_save
        save_state(@quick_save_slot)
      end

      # Load from the quick save slot.
      # @return [Array(Boolean, String)]
      def quick_load
        load_state(@quick_save_slot)
      end

      # Save a PNG screenshot of the current frame via Tk photo image.
      # Uses @app.command() to drive Tk's image subsystem.
      # @param path [String] output PNG file path
      def save_screenshot(path)
        return unless @core && !@core.destroyed?

        pixels = @core.video_buffer_argb
        photo_name = "__teek_ss_#{object_id}"

        @app.command(:image, :create, :photo, photo_name,
                     width: GBA_W, height: GBA_H)
        @app.interp.photo_put_block(photo_name, pixels, GBA_W, GBA_H, format: :argb)
        @app.command(photo_name, :write, path, format: :png)
        @app.command(:image, :delete, photo_name)
      rescue StandardError => e
        warn "teek-mgba: screenshot failed for #{path}: #{e.message} (#{e.class})"
        @app.command(:image, :delete, photo_name) rescue nil
      end
    end
  end
end
