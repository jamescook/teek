# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'set'
require 'teek/platform'

module Teek
  module MGBA
    # Persists mGBA Player settings to a JSON file in the platform-appropriate
    # config directory.
    #
    # Config file location:
    #   macOS:   ~/Library/Application Support/teek-mgba/settings.json
    #   Linux:   $XDG_CONFIG_HOME/teek-mgba/settings.json  (~/.config/teek-mgba/)
    #   Windows: %APPDATA%/teek-mgba/settings.json
    #
    # Gamepad mappings are keyed by SDL GUID (identifies controller model/type),
    # so different controller types keep separate configs.
    #
    # Per-game settings: when enabled, a subset of settings (video, audio,
    # save state) can be overridden per ROM. Game-specific files are stored
    # under config_dir/games/<rom_id>/settings.json. The PerGameProxy class
    # transparently routes reads/writes so callers don't need conditionals.
    class Config
      APP_NAME = 'teek-mgba'
      FILENAME = 'settings.json'

      GLOBAL_DEFAULTS = {
        'scale'              => 3,
        'volume'             => 100,
        'muted'              => false,
        'turbo_speed'        => 2,
        'turbo_volume_pct'   => 25,
        'keep_aspect_ratio'  => true,
        'show_fps'           => true,
        'toast_duration'     => 1.5,
        'save_state_debounce' => 3.0,
        'quick_save_slot'    => 1,
        'save_state_backup'  => true,
        'locale'             => 'auto',
        'pixel_filter'       => 'nearest',
        'integer_scale'      => false,
        'color_correction'   => false,
        'frame_blending'     => false,
        'rewind_enabled'     => true,
        'rewind_seconds'     => 10,
        'per_game_settings'  => false,
        'tip_dismiss_ms'     => 4000,
        'recording_compression' => 1,
      }.freeze

      # Settings that can be overridden per ROM. Maps config key → locale key.
      # This is the single source of truth for which keys are per-game eligible.
      PER_GAME_SETTINGS = {
        'scale'             => 'settings.window_scale',
        'pixel_filter'      => 'settings.pixel_filter',
        'integer_scale'     => 'settings.integer_scale',
        'color_correction'  => 'settings.color_correction',
        'frame_blending'    => 'settings.frame_blending',
        'volume'            => 'settings.volume',
        'muted'             => 'settings.mute',
        'turbo_speed'       => 'settings.turbo_speed',
        'quick_save_slot'   => 'settings.quick_save_slot',
        'save_state_backup' => 'settings.keep_backup',
      }.freeze

      PER_GAME_KEYS = PER_GAME_SETTINGS.keys.to_set.freeze

      # Transparent proxy that routes per-game keys to a game-specific hash
      # and everything else to the base (global) hash. Config getters/setters
      # call global['key'] — this intercepts those calls so no other code
      # needs to know whether per-game settings are active.
      class PerGameProxy
        def initialize(base, game_data, per_game_keys)
          @base = base
          @game_data = game_data
          @per_game_keys = per_game_keys
        end

        def [](key)
          if @per_game_keys.include?(key) && @game_data.key?(key)
            @game_data[key]
          else
            @base[key]
          end
        end

        def []=(key, val)
          if @per_game_keys.include?(key)
            @game_data[key] = val
          else
            @base[key] = val
          end
        end
      end

      GAMEPAD_DEFAULTS = {
        'dead_zone' => 25,
        'mappings'  => {
          'a' => 'a', 'b' => 'b',
          'l' => 'left_shoulder', 'r' => 'right_shoulder',
          'up' => 'dpad_up', 'down' => 'dpad_down',
          'left' => 'dpad_left', 'right' => 'dpad_right',
          'start' => 'start', 'select' => 'back',
        },
      }.freeze

      # Sentinel GUID for keyboard bindings — stored alongside real gamepad GUIDs.
      KEYBOARD_GUID = 'keyboard'

      MAX_RECENT_ROMS = 5

      KEYBOARD_DEFAULTS = {
        'dead_zone' => 0,
        'mappings'  => {
          'a' => 'z', 'b' => 'x',
          'l' => 'a', 'r' => 's',
          'up' => 'Up', 'down' => 'Down',
          'left' => 'Left', 'right' => 'Right',
          'start' => 'Return', 'select' => 'BackSpace',
        },
      }.freeze

      def initialize(path: nil)
        @path = path || self.class.default_path
        @data = load_file
      end

      # @return [String] path to the config file
      attr_accessor :path

      # -- Global settings ---------------------------------------------------

      def scale
        global['scale']
      end

      def scale=(val)
        global['scale'] = val.to_i.clamp(1, 4)
      end

      def volume
        global['volume']
      end

      def volume=(val)
        global['volume'] = val.to_i.clamp(0, 100)
      end

      def muted?
        global['muted']
      end

      def muted=(val)
        global['muted'] = !!val
      end

      # @return [Integer] turbo speed multiplier (2, 3, 4, or 0 for uncapped)
      def turbo_speed
        global['turbo_speed']
      end

      def turbo_speed=(val)
        global['turbo_speed'] = val.to_i
      end

      # @return [Integer] volume percentage during fast-forward (0-100, hidden setting)
      def turbo_volume_pct
        global['turbo_volume_pct']
      end

      def turbo_volume_pct=(val)
        global['turbo_volume_pct'] = val.to_i.clamp(0, 100)
      end

      def keep_aspect_ratio?
        global['keep_aspect_ratio']
      end

      def keep_aspect_ratio=(val)
        global['keep_aspect_ratio'] = !!val
      end

      def show_fps?
        global['show_fps']
      end

      def show_fps=(val)
        global['show_fps'] = !!val
      end

      # @return [String] pixel filter mode ('nearest' or 'linear')
      def pixel_filter
        global['pixel_filter']
      end

      def pixel_filter=(val)
        global['pixel_filter'] = %w[nearest linear].include?(val.to_s) ? val.to_s : 'nearest'
      end

      def integer_scale?
        global['integer_scale']
      end

      def integer_scale=(val)
        global['integer_scale'] = !!val
      end

      def color_correction?
        global['color_correction']
      end

      def color_correction=(val)
        global['color_correction'] = !!val
      end

      def frame_blending?
        global['frame_blending']
      end

      def frame_blending=(val)
        global['frame_blending'] = !!val
      end

      def rewind_enabled?
        global['rewind_enabled']
      end

      def rewind_enabled=(val)
        global['rewind_enabled'] = !!val
      end

      # @return [Integer] rewind buffer duration in seconds (1-60)
      def rewind_seconds
        global['rewind_seconds']
      end

      def rewind_seconds=(val)
        global['rewind_seconds'] = val.to_i.clamp(1, 60)
      end

      # -- Per-game settings ---------------------------------------------------

      # @return [Boolean] whether per-game settings are enabled
      def per_game_settings?
        !!global_base['per_game_settings']
      end

      def per_game_settings=(val)
        global_base['per_game_settings'] = !!val
      end

      # @return [String, nil] the active ROM ID, or nil if no ROM loaded
      attr_reader :active_rom_id

      # Activate per-game config for the given ROM. If per_game_settings? is
      # true, reads/writes to PER_GAME_KEYS will go through the game file.
      # @param rom_id [String] e.g. "AGB_BTKE-DEADBEEF"
      def activate_game(rom_id)
        @active_rom_id = rom_id
        if per_game_settings?
          @game_data = load_game_file(rom_id)
          @proxy = PerGameProxy.new(global_base, @game_data, PER_GAME_KEYS)
        else
          @game_data = nil
          @proxy = nil
        end
      end

      # Deactivate per-game settings (e.g. when ROM is unloaded).
      def deactivate_game
        @active_rom_id = nil
        @game_data = nil
        @proxy = nil
      end

      # Enable per-game settings for the currently loaded ROM.
      # Copies current global values to game file on first enable.
      def enable_per_game
        raise "No ROM loaded" unless @active_rom_id
        self.per_game_settings = true
        @game_data = load_game_file(@active_rom_id)
        if @game_data.empty?
          PER_GAME_KEYS.each { |key| @game_data[key] = global_base[key] }
        end
        @proxy = PerGameProxy.new(global_base, @game_data, PER_GAME_KEYS)
      end

      # Disable per-game settings. Reverts to global values.
      # Does NOT delete the game-specific file on disk.
      def disable_per_game
        self.per_game_settings = false
        @proxy = nil
      end

      # Build a ROM identifier from game code and CRC32 checksum.
      # Uses the same sanitization as SaveStateManager#state_dir_for_rom.
      # @return [String] e.g. "AGB_BTKE-DEADBEEF"
      def self.rom_id(game_code, checksum)
        code = game_code.gsub(/[^a-zA-Z0-9_.-]/, '_')
        crc  = format('%08X', checksum)
        "#{code}-#{crc}"
      end

      # @return [String] path to the per-game settings file
      def self.game_config_path(rom_id)
        File.join(config_dir, 'games', rom_id, 'settings.json')
      end

      # @return [Float] toast notification duration in seconds
      def toast_duration
        global['toast_duration'].to_f
      end

      def toast_duration=(val)
        val = val.to_f
        raise ArgumentError, "toast_duration must be positive" if val <= 0
        global['toast_duration'] = val.clamp(0.1, 10.0)
      end

      # @return [String] directory for game save files (.sav)
      def saves_dir
        global['saves_dir'] || self.class.default_saves_dir
      end

      def saves_dir=(val)
        global['saves_dir'] = val.to_s
      end

      # @return [String] directory for save state files (.ss1, .ss2, etc.)
      def states_dir
        global['states_dir'] || self.class.default_states_dir
      end

      def states_dir=(val)
        global['states_dir'] = val.to_s
      end

      # @return [Integer] tooltip auto-dismiss delay in milliseconds (hidden setting)
      def tip_dismiss_ms
        global['tip_dismiss_ms']
      end

      def tip_dismiss_ms=(val)
        global['tip_dismiss_ms'] = val.to_i.clamp(1000, 30_000)
      end

      # @return [Float] debounce interval in seconds between save state operations (hidden setting)
      def save_state_debounce
        global['save_state_debounce'].to_f
      end

      def save_state_debounce=(val)
        global['save_state_debounce'] = val.to_f.clamp(0.0, 30.0)
      end

      # @return [Integer] quick save/load slot (1-10)
      def quick_save_slot
        global['quick_save_slot']
      end

      def quick_save_slot=(val)
        global['quick_save_slot'] = val.to_i.clamp(1, 10)
      end

      # @return [Boolean] whether to create .bak files when overwriting save states
      def save_state_backup?
        global['save_state_backup']
      end

      def save_state_backup=(val)
        global['save_state_backup'] = !!val
      end

      # @return [String] locale code ('auto', 'en', 'ja', etc.)
      def locale
        global['locale']
      end

      def locale=(val)
        global['locale'] = val.to_s
      end

      # @return [Integer] zlib compression level for .trec recordings (1-9)
      def recording_compression
        global['recording_compression']
      end

      def recording_compression=(val)
        global['recording_compression'] = val.to_i.clamp(1, 9)
      end

      # @return [String] directory for .trec recording files
      def recordings_dir
        global['recordings_dir'] || self.class.default_recordings_dir
      end

      def recordings_dir=(val)
        global['recordings_dir'] = val.to_s
      end

      # -- Recent ROMs -------------------------------------------------------

      # @return [Array<String>] ROM paths, newest first
      def recent_roms
        @data['recent_roms'] ||= []
      end

      # Add a ROM path to the front of the recent list (deduplicates).
      # @param path [String] absolute path to the ROM file
      def add_recent_rom(path)
        list = recent_roms
        list.delete(path)
        list.unshift(path)
        list.pop while list.size > MAX_RECENT_ROMS
      end

      # Remove a specific ROM path from the recent list.
      # @param path [String]
      def remove_recent_rom(path)
        recent_roms.delete(path)
      end

      def clear_recent_roms
        @data['recent_roms'] = []
      end

      # -- Hotkeys -------------------------------------------------------------

      # @return [Hash] action (String) → keysym (String)
      def hotkeys
        @data['hotkeys'] ||= {}
      end

      # @param action [Symbol, String] e.g. :quit, 'pause'
      # @param hk [String, Array] e.g. 'q', 'F5', or ['Control', 's']
      def set_hotkey(action, hk)
        hotkeys[action.to_s] = hk
      end

      def reset_hotkeys
        @data['hotkeys'] = {}
      end

      # -- Per-gamepad settings ----------------------------------------------

      # @param guid [String] SDL joystick GUID, or KEYBOARD_GUID for keyboard bindings
      # @param name [String] human-readable controller name (stored for reference)
      # @return [Hash] gamepad config (dead_zone, mappings)
      def gamepad(guid, name: nil)
        defaults = guid == KEYBOARD_GUID ? KEYBOARD_DEFAULTS : GAMEPAD_DEFAULTS
        gp = gamepads[guid] ||= deep_dup(defaults)
        gp['name'] = name if name
        gp
      end

      # @param guid [String]
      # @return [Integer] dead zone percentage (0-50)
      def dead_zone(guid)
        gamepad(guid)['dead_zone']
      end

      # @param guid [String]
      # @param val [Integer] percentage (0-50)
      def set_dead_zone(guid, val)
        gamepad(guid)['dead_zone'] = val.to_i.clamp(0, 50)
      end

      # @param guid [String]
      # @return [Hash] GBA button (String) → gamepad button (String)
      def mappings(guid)
        gamepad(guid)['mappings']
      end

      # @param guid [String]
      # @param gba_btn [Symbol, String] e.g. :a, "a"
      # @param gp_btn [Symbol, String] e.g. :x, "dpad_up"
      def set_mapping(guid, gba_btn, gp_btn)
        m = gamepad(guid)['mappings']
        m.delete_if { |_, v| v == gp_btn.to_s }
        m[gba_btn.to_s] = gp_btn.to_s
      end

      # @param guid [String]
      def reset_gamepad(guid)
        defaults = guid == KEYBOARD_GUID ? KEYBOARD_DEFAULTS : GAMEPAD_DEFAULTS
        gamepads[guid] = deep_dup(defaults)
      end

      # -- Persistence -------------------------------------------------------

      def save!
        @data['meta'] = {
          'teek_version'      => (defined?(Teek::VERSION) && Teek::VERSION) || 'unknown',
          'teek_mgba_version' => (defined?(Teek::MGBA::VERSION) && Teek::MGBA::VERSION) || 'unknown',
          'saved_at'          => Time.now.iso8601,
        }
        dir = File.dirname(@path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        File.write(@path, JSON.pretty_generate(@data))

        save_game_file! if @game_data && @active_rom_id
      end

      def reload!
        @data = load_file
        activate_game(@active_rom_id) if @active_rom_id
      end

      # -- Platform paths ----------------------------------------------------

      def self.default_path
        File.join(config_dir, FILENAME)
      end

      # Delete the settings file at the given path (or the default).
      # @return [String, nil] the path deleted, or nil if no file existed
      def self.reset!(path: default_path)
        if File.exist?(path)
          File.delete(path)
          path
        end
      end

      def self.config_dir
        p = Teek.platform
        if p.darwin?
          File.join(Dir.home, 'Library', 'Application Support', APP_NAME)
        elsif p.windows?
          File.join(ENV.fetch('APPDATA', File.join(Dir.home, 'AppData', 'Roaming')), APP_NAME)
        else
          # Linux / other Unix — XDG Base Directory Specification
          base = ENV.fetch('XDG_CONFIG_HOME', File.join(Dir.home, '.config'))
          File.join(base, APP_NAME)
        end
      end

      # @return [String] default directory for game save files (.sav)
      def self.default_saves_dir
        File.join(config_dir, 'saves')
      end

      # @return [String] default directory for save state files
      def self.default_states_dir
        File.join(config_dir, 'states')
      end

      # @return [String] default directory for screenshots
      def self.default_screenshots_dir
        File.join(config_dir, 'screenshots')
      end

      # @return [String] default directory for .trec recordings
      def self.default_recordings_dir
        File.join(config_dir, 'recordings')
      end

      private

      def global
        @proxy || global_base
      end

      def global_base
        @data['global'] ||= deep_dup(GLOBAL_DEFAULTS)
      end

      def gamepads
        @data['gamepads'] ||= {}
      end

      def load_file
        return default_data unless File.exist?(@path)

        data = JSON.parse(File.read(@path))
        data['global'] = GLOBAL_DEFAULTS.merge(data['global'] || {})
        data['gamepads'] ||= {}
        data['recent_roms'] ||= []
        data
      rescue JSON::ParserError => e
        warn "teek-mgba: corrupt config file #{@path}: #{e.message} — using defaults"
        default_data
      end

      def default_data
        { 'global' => deep_dup(GLOBAL_DEFAULTS), 'gamepads' => {}, 'recent_roms' => [] }
      end

      def deep_dup(hash)
        JSON.parse(JSON.generate(hash))
      end

      def load_game_file(rom_id)
        path = self.class.game_config_path(rom_id)
        return {} unless File.exist?(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        warn "teek-mgba: corrupt game config #{path}: #{e.message} — using global"
        {}
      end

      def save_game_file!
        path = self.class.game_config_path(@active_rom_id)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        File.write(path, JSON.pretty_generate(@game_data))
      end
    end
  end
end
