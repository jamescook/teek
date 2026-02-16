# frozen_string_literal: true

require 'fileutils'
require_relative 'locale'

module Teek
  module MGBA
    # Full-featured GBA frontend powered by teek + teek-sdl2.
    #
    # Renders GBA games at 3x native resolution with audio and
    # keyboard/gamepad input. Uses wall-clock frame pacing with
    # Near/byuu dynamic rate control for audio sync.
    #
    # @example Launch with a ROM
    #   Teek::MGBA::Player.new("pokemon.gba").run
    #
    # @example Launch without a ROM (use File > Open ROM...)
    #   Teek::MGBA::Player.new.run
    class Player
      include Teek::MGBA
      include Locale::Translatable

      GBA_W  = 240
      GBA_H  = 160
      DEFAULT_SCALE = 3

      # GBA audio: mGBA outputs at 44100 Hz (stereo int16)
      AUDIO_FREQ     = 44100
      GBA_FPS        = 59.7272
      FRAME_PERIOD   = 1.0 / GBA_FPS

      # Dynamic rate control constants (see tick_normal for the math)
      AUDIO_BUF_CAPACITY = (AUDIO_FREQ / GBA_FPS * 6).to_i  # ~6 frames (~100ms)
      MAX_DELTA          = 0.005                              # ±0.5% max adjustment
      FF_MAX_FRAMES      = 10  # cap for uncapped turbo to avoid locking event loop
      SAVE_STATE_DEBOUNCE_DEFAULT = 3.0 # seconds; overridden by config
      SAVE_STATE_SLOTS    = 10
      FADE_IN_FRAMES     = (AUDIO_FREQ * 0.02).to_i  # ~20ms = 882 samples
      GAMEPAD_PROBE_MS   = 2000
      GAMEPAD_LISTEN_MS  = 50

      # Modal child window types → locale keys for the window title overlay
      MODAL_LABELS = {
        settings: 'menu.settings',
        picker: 'menu.save_states',
        rom_info: 'menu.rom_info',
      }.freeze

      def initialize(rom_path = nil, sound: true, fullscreen: false, frames: nil)
        @app = Teek::App.new
        @app.interp.thread_timer_ms = 1  # need fast event dispatch for emulation
        @app.show

        @sound = sound
        @config = Teek::MGBA.user_config
        @scale  = @config.scale
        @volume = @config.volume / 100.0
        @muted  = @config.muted?
        @kb_map  = KeyboardMap.new(@config)
        @gp_map  = GamepadMap.new(@config)
        @keyboard = VirtualKeyboard.new
        @kb_map.device = @keyboard
        @hotkeys = HotkeyMap.new(@config)
        @turbo_speed = @config.turbo_speed
        @turbo_volume = @config.turbo_volume_pct / 100.0
        @keep_aspect_ratio = @config.keep_aspect_ratio?
        @show_fps = @config.show_fps?
        @pixel_filter = @config.pixel_filter
        @integer_scale = @config.integer_scale?
        @color_correction = @config.color_correction?
        @frame_blending = @config.frame_blending?
        @rewind_enabled = @config.rewind_enabled?
        @rewind_seconds = @config.rewind_seconds
        @rewind_frame_counter = 0
        @audio_fade_in = 0
        @frame_limit = frames
        @total_frames = 0
        @fast_forward = false
        @fullscreen = fullscreen
        @quick_save_slot = @config.quick_save_slot
        @save_state_backup = @config.save_state_backup?
        @save_mgr = nil  # created when ROM loaded
        @recorder = nil
        @recording_compression = @config.recording_compression
        check_writable_dirs

        win_w = GBA_W * @scale
        win_h = GBA_H * @scale
        @app.set_window_title("mGBA Player")
        @app.set_window_geometry("#{win_w}x#{win_h}")

        build_menu

        @rom_info_window = RomInfoWindow.new(@app, callbacks: {
          on_close: method(:on_child_window_close),
        })
        @state_picker = SaveStatePicker.new(@app, callbacks: {
          on_save: method(:save_state),
          on_load: method(:load_state),
          on_close: method(:on_child_window_close),
        })

        @settings_window = SettingsWindow.new(@app, tip_dismiss_ms: @config.tip_dismiss_ms, callbacks: {
          on_scale_change:        method(:apply_scale),
          on_volume_change:       method(:apply_volume),
          on_mute_change:         method(:apply_mute),
          on_gamepad_map_change:  ->(btn, gp) { active_input.set(btn, gp) },
          on_keyboard_map_change: ->(btn, key) { active_input.set(btn, key) },
          on_deadzone_change:     ->(val) { active_input.set_dead_zone(val) },
          on_gamepad_reset:       -> { active_input.reset! },
          on_keyboard_reset:      -> { active_input.reset! },
          on_undo_gamepad:        method(:undo_mappings),
          on_validate_hotkey:     method(:validate_hotkey),
          on_validate_kb_mapping: method(:validate_kb_mapping),
          on_hotkey_change:       ->(action, key) { @hotkeys.set(action, key) },
          on_hotkey_reset:        -> { @hotkeys.reset! },
          on_undo_hotkeys:        method(:undo_hotkeys),
          on_turbo_speed_change:  method(:apply_turbo_speed),
          on_aspect_ratio_change: method(:apply_aspect_ratio),
          on_show_fps_change:     method(:apply_show_fps),
          on_filter_change:       method(:apply_pixel_filter),
          on_integer_scale_change: method(:apply_integer_scale),
          on_color_correction_change: method(:apply_color_correction),
          on_frame_blending_change:   method(:apply_frame_blending),
          on_rewind_toggle:          method(:apply_rewind_toggle),
          on_per_game_toggle:        method(:toggle_per_game),
          on_toast_duration_change: method(:apply_toast_duration),
          on_quick_slot_change:   method(:apply_quick_slot),
          on_backup_change:       method(:apply_backup),
          on_compression_change:  method(:apply_recording_compression),
          on_open_config_dir:     method(:open_config_dir),
          on_open_recordings_dir: method(:open_recordings_dir),
          on_close:               method(:on_child_window_close),
          on_save:                method(:save_config),
        })

        # Push loaded config into the settings UI
        @settings_window.refresh_gamepad(@kb_map.labels, @kb_map.dead_zone_pct)
        @settings_window.refresh_hotkeys(@hotkeys.labels)
        push_settings_to_ui

        # Input/emulation state (initialized before SDL2)
        @gamepad = nil
        @running = true
        @paused = false
        @core = nil
        @rom_path = nil
        @initial_rom = rom_path
        @modal_child = nil  # tracks which child window is open

        # Block interaction until SDL2 is ready
        @app.command('tk', 'busy', '.')
      end

      # @return [Teek::App]
      attr_reader :app

      # @return [Teek::MGBA::Config]
      attr_reader :config

      # @return [Teek::MGBA::Viewport, nil] nil until SDL2 init
      attr_reader :viewport

      # @return [Teek::MGBA::Core, nil] nil until ROM loaded
      attr_reader :core

      # @return [Teek::MGBA::Recorder, nil] nil when not recording
      attr_reader :recorder

      # @return [Boolean] whether the main loop is running
      attr_accessor :running

      # @return [Integer] current video scale multiplier
      attr_reader :scale

      # @return [Float] current audio volume (0.0-1.0)
      attr_reader :volume

      # @return [Boolean] whether audio is muted
      def muted?
        @muted
      end

      # @return [Boolean] whether currently recording
      def recording?
        @recorder&.recording? || false
      end

      # @return [Teek::MGBA::SettingsWindow]
      attr_reader :settings_window

      # @return [Teek::MGBA::SaveStateManager, nil] nil until ROM loaded
      attr_reader :save_mgr

      # @return [Teek::MGBA::KeyboardMap]
      attr_reader :kb_map

      # @return [Teek::MGBA::GamepadMap]
      attr_reader :gp_map

      def run
        @sdl2_init_started = false
        @app.after(1) do
          @sdl2_init_started = true
          init_sdl2
        end
        @app.mainloop
      ensure
        unless @sdl2_init_started
          $stderr.puts "FATAL: init_sdl2 callback never fired (event loop exited early)"
        end
        cleanup
      end

      private

      # Deferred SDL2 initialization — runs inside the event loop so the
      # window is already painted and responsive. Without this, the heavy
      # SDL2 C calls (renderer, audio device, gamepad IOKit) block the
      # main thread before macOS has a chance to display the window,
      # causing a brief spinning beach ball.
      def init_sdl2
        win_w = GBA_W * @scale
        win_h = GBA_H * @scale

        @viewport = Teek::SDL2::Viewport.new(@app, width: win_w, height: win_h, vsync: false)
        @viewport.pack(fill: :both, expand: true)

        # Status label overlaid on viewport (shown when no ROM loaded)
        @status_label = '.status_overlay'
        @app.command(:label, @status_label,
          text: translate('player.open_rom_hint'),
          fg: '#888888', bg: '#000000',
          font: '{TkDefaultFont} 11')
        @app.command(:place, @status_label,
          in: @viewport.frame.path,
          relx: 0.5, rely: 0.85, anchor: :center)

        # Streaming texture at native GBA resolution
        @texture = @viewport.renderer.create_texture(GBA_W, GBA_H, :streaming)
        @texture.scale_mode = @pixel_filter.to_sym

        # Font for on-screen indicators (FPS, fast-forward label)
        font_path = File.join(ASSETS_DIR, 'JetBrainsMonoNL-Regular.ttf')
        @overlay_font = File.exist?(font_path) ? @viewport.renderer.load_font(font_path, 14) : nil

        # CJK-capable font for toast notifications and translated UI text
        toast_font_path = File.join(ASSETS_DIR, 'ark-pixel-12px-monospaced-ja.ttf')
        toast_font = File.exist?(toast_font_path) ? @viewport.renderer.load_font(toast_font_path, 12) : @overlay_font

        @toast = ToastOverlay.new(
          renderer: @viewport.renderer,
          font: toast_font || @overlay_font,
          duration: @config.toast_duration
        )

        # Custom blend mode: white text inverts the background behind it.
        # dstRGB = (1 - dstRGB) * srcRGB + dstRGB * (1 - srcA)
        # Where srcA=1 (opaque text): result = 1 - dst  (inverted)
        # Where srcA=0 (transparent): result = dst      (unchanged)
        inverse_blend = Teek::SDL2.compose_blend_mode(
          :one_minus_dst_color, :one_minus_src_alpha, :add,
          :zero, :one, :add
        )

        @hud = OverlayRenderer.new(font: @overlay_font, blend_mode: inverse_blend)

        # Audio stream — stereo int16 at GBA sample rate.
        # Falls back to a silent no-op stream when sound is disabled or
        # no audio device is available (e.g. CI servers, headless).
        if @sound && Teek::SDL2::AudioStream.available?
          @stream = Teek::SDL2::AudioStream.new(
            frequency: AUDIO_FREQ,
            format:    :s16,
            channels:  2
          )
          @stream.resume
        else
          warn "mGBA Player: no audio device found, continuing without sound" if @sound
          @stream = Teek::SDL2::NullAudioStream.new
        end

        # Initialize gamepad subsystem for hot-plug detection
        Teek::SDL2::Gamepad.init_subsystem
        Teek::SDL2::Gamepad.on_added { |_| refresh_gamepads }
        Teek::SDL2::Gamepad.on_removed { |_| @gamepad = nil; @gp_map.device = nil; refresh_gamepads }
        refresh_gamepads
        start_gamepad_probe

        setup_input
        setup_drop_target

        load_rom(@initial_rom) if @initial_rom

        # Apply fullscreen before unblocking (set via CLI --fullscreen)
        @app.command(:wm, 'attributes', '.', '-fullscreen', 1) if @fullscreen

        # Unblock interaction now that SDL2 is ready
        @app.command('tk', 'busy', 'forget', '.')

        # Auto-focus viewport for keyboard input
        @app.tcl_eval("focus -force #{@viewport.frame.path}")
        @app.update

        animate
      rescue => e
        # Surface init failures visibly — Tk's event loop can swallow
        # exceptions from `after` callbacks, causing silent hangs.
        $stderr.puts "FATAL: init_sdl2 failed: #{e.class}: #{e.message}"
        $stderr.puts e.backtrace.first(10).map { |l| "  #{l}" }.join("\n")
        @app.command('tk', 'busy', 'forget', '.') rescue nil
        @running = false
      end

      def show_rom_info
        return unless @core && !@core.destroyed?
        return bell if @modal_child
        @modal_child = :rom_info
        enter_modal
        saves = @config.saves_dir
        sav_name = File.basename(@rom_path, File.extname(@rom_path)) + '.sav'
        sav_path = File.join(saves, sav_name)
        @rom_info_window.show(@core, rom_path: @rom_path, save_path: sav_path)
      end

      # -- Save states (delegated to SaveStateManager) -------------------------

      def save_state(slot)
        return unless @save_mgr
        _ok, msg = @save_mgr.save_state(slot)
        @toast&.show(msg) if msg
      end

      def load_state(slot)
        return unless @save_mgr
        _ok, msg = @save_mgr.load_state(slot)
        @toast&.show(msg) if msg
      end

      def quick_save
        return unless @save_mgr
        _ok, msg = @save_mgr.quick_save
        @toast&.show(msg) if msg
      end

      def quick_load
        return unless @save_mgr
        _ok, msg = @save_mgr.quick_load
        @toast&.show(msg) if msg
      end

      def take_screenshot
        return unless @core && !@core.destroyed?

        dir = Config.default_screenshots_dir
        FileUtils.mkdir_p(dir)

        title = @core.title.strip.gsub(/[^a-zA-Z0-9_\-]/, '_')
        stamp = Time.now.strftime('%Y%m%d_%H%M%S')
        name = "#{title}_#{stamp}.png"
        path = File.join(dir, name)

        pixels = @core.video_buffer_argb
        photo_name = "__teek_ss_#{object_id}"
        out_w = GBA_W * @scale
        out_h = GBA_H * @scale
        @app.command(:image, :create, :photo, photo_name,
                     width: out_w, height: out_h)
        @app.interp.photo_put_zoomed_block(photo_name, pixels, GBA_W, GBA_H,
                                           zoom_x: @scale, zoom_y: @scale, format: :argb)
        @app.command(photo_name, :write, path, format: :png)
        @app.command(:image, :delete, photo_name)
        @toast&.show(translate('toast.screenshot_saved', name: name))
      rescue StandardError => e
        warn "teek-mgba: screenshot failed: #{e.message} (#{e.class})"
        @app.command(:image, :delete, photo_name) rescue nil
        @toast&.show(translate('toast.screenshot_failed'))
      end

      def show_settings(tab: nil)
        return bell if @modal_child
        @modal_child = :settings
        enter_modal
        @settings_window.show(tab: tab)
      end

      def show_state_picker
        return unless @save_mgr&.state_dir
        return bell if @modal_child
        @modal_child = :picker
        enter_modal
        @state_picker.show(state_dir: @save_mgr.state_dir, quick_slot: @quick_save_slot)
      end

      def on_child_window_close
        @toast&.destroy
        toggle_pause if @core && !@was_paused_before_modal
        @modal_child = nil
      end

      def enter_modal
        @was_paused_before_modal = @paused
        toggle_fast_forward if @fast_forward
        toggle_pause if @core && !@paused
        locale_key = MODAL_LABELS[@modal_child] || @modal_child.to_s
        label = translate(locale_key)
        @toast&.show(translate('toast.waiting_for', label: label), permanent: true)
      end

      def bell
        @app.command(:bell)
      end

      def show_rom_error(message)
        @app.command('tk_messageBox',
          parent: '.',
          title: translate('dialog.drop_error_title'),
          message: message,
          type: :ok,
          icon: :error)
      end

      def save_config
        @config.scale = @scale
        @config.volume = (@volume * 100).round
        @config.muted = @muted
        @config.turbo_speed = @turbo_speed
        @config.keep_aspect_ratio = @keep_aspect_ratio
        @config.show_fps = @show_fps
        @config.pixel_filter = @pixel_filter
        @config.integer_scale = @integer_scale
        @config.color_correction = @color_correction
        @config.frame_blending = @frame_blending
        @config.rewind_enabled = @rewind_enabled
        @config.rewind_seconds = @rewind_seconds
        @config.quick_save_slot = @quick_save_slot
        @config.save_state_backup = @save_state_backup
        @config.recording_compression = @recording_compression

        @kb_map.save_to_config
        @gp_map.save_to_config
        @hotkeys.save_to_config
        @config.save!
      end

      def apply_scale(new_scale)
        @scale = new_scale.clamp(1, 4)
        w = GBA_W * @scale
        h = GBA_H * @scale
        @app.set_window_geometry("#{w}x#{h}")
      end

      def apply_volume(vol)
        @volume = vol.to_f.clamp(0.0, 1.0)
      end

      def apply_mute(muted)
        @muted = !!muted
      end

      def apply_pixel_filter(filter)
        @pixel_filter = filter
        @texture.scale_mode = filter.to_sym if @texture
      end

      def apply_integer_scale(enabled)
        @integer_scale = !!enabled
      end

      def apply_color_correction(enabled)
        @color_correction = !!enabled
        if @core && !@core.destroyed?
          @core.color_correction = @color_correction
          render_frame if @texture
        end
      end

      def apply_frame_blending(enabled)
        @frame_blending = !!enabled
        if @core && !@core.destroyed?
          @core.frame_blending = @frame_blending
          render_frame if @texture
        end
      end

      def apply_rewind_toggle(enabled)
        @rewind_enabled = !!enabled
        if @core && !@core.destroyed?
          if @rewind_enabled
            @core.rewind_init(@rewind_seconds)
            @rewind_frame_counter = 0
          else
            @core.rewind_deinit
          end
        end
      end

      def do_rewind
        return unless @core && !@core.destroyed?
        unless @rewind_enabled
          @toast&.show(translate('toast.no_rewind'))
          return
        end
        if @core.rewind_pop == true
          @core.run_frame # refresh video buffer from restored state
          @stream.clear
          @audio_fade_in = FADE_IN_FRAMES
          @rewind_frame_counter = 0
          render_frame
          @toast&.show(translate('toast.rewound'))
        else
          @toast&.show(translate('toast.no_rewind'))
        end
      end

      def toggle_per_game(enabled)
        if enabled
          @config.enable_per_game
        else
          @config.disable_per_game
        end
        refresh_from_config
      end

      # Re-read per-game-eligible settings from config and apply them.
      def refresh_from_config
        @scale            = @config.scale
        @volume           = @config.volume / 100.0
        @muted            = @config.muted?
        @turbo_speed      = @config.turbo_speed
        @pixel_filter     = @config.pixel_filter
        @integer_scale    = @config.integer_scale?
        @color_correction = @config.color_correction?
        @frame_blending   = @config.frame_blending?
        @rewind_enabled   = @config.rewind_enabled?
        @rewind_seconds   = @config.rewind_seconds
        @quick_save_slot  = @config.quick_save_slot
        @save_state_backup = @config.save_state_backup?
        @recording_compression = @config.recording_compression

        push_settings_to_ui

        # Apply runtime effects
        apply_scale(@scale) if @viewport
        @texture.scale_mode = @pixel_filter.to_sym if @texture
        if @core && !@core.destroyed?
          @core.color_correction = @color_correction
          @core.frame_blending = @frame_blending
          render_frame if @texture
        end
        @save_mgr.quick_save_slot = @quick_save_slot if @save_mgr
        @save_mgr.backup = @save_state_backup if @save_mgr
      end

      # Push current instance vars to settings window UI variables.
      def push_settings_to_ui
        @app.set_variable(SettingsWindow::VAR_SCALE, "#{@scale}x")
        turbo_label = @turbo_speed == 0 ? 'Uncapped' : "#{@turbo_speed}x"
        @app.set_variable(SettingsWindow::VAR_TURBO, turbo_label)
        @app.set_variable(SettingsWindow::VAR_ASPECT_RATIO, @keep_aspect_ratio ? '1' : '0')
        @app.set_variable(SettingsWindow::VAR_SHOW_FPS, @show_fps ? '1' : '0')
        toast_label = "#{@config.toast_duration}s"
        @app.set_variable(SettingsWindow::VAR_TOAST_DURATION, toast_label)
        filter_label = @pixel_filter == 'nearest' ? @settings_window.send(:translate, 'settings.filter_nearest') : @settings_window.send(:translate, 'settings.filter_linear')
        @app.set_variable(SettingsWindow::VAR_FILTER, filter_label)
        @app.set_variable(SettingsWindow::VAR_INTEGER_SCALE, @integer_scale ? '1' : '0')
        @app.set_variable(SettingsWindow::VAR_COLOR_CORRECTION, @color_correction ? '1' : '0')
        @app.set_variable(SettingsWindow::VAR_FRAME_BLENDING, @frame_blending ? '1' : '0')
        @app.set_variable(SettingsWindow::VAR_REWIND_ENABLED, @rewind_enabled ? '1' : '0')
        @app.set_variable(SettingsWindow::VAR_VOLUME, (@volume * 100).round.to_s)
        @app.set_variable(SettingsWindow::VAR_MUTE, @muted ? '1' : '0')
        @app.set_variable(SettingsWindow::VAR_QUICK_SLOT, @quick_save_slot.to_s)
        @app.set_variable(SettingsWindow::VAR_SS_BACKUP, @save_state_backup ? '1' : '0')
        @app.set_variable(SettingsWindow::VAR_REC_COMPRESSION, @recording_compression.to_s)
      end

      # Returns the currently active input map based on settings window mode.
      def active_input
        @settings_window.keyboard_mode? ? @kb_map : @gp_map
      end

      # Undo: reload mappings from disk for the active input device.
      def undo_mappings
        input = active_input
        input.reload!
        @settings_window.refresh_gamepad(input.labels, input.dead_zone_pct)
      end

      # Undo: reload hotkeys from disk.
      def undo_hotkeys
        @hotkeys.reload!
        @settings_window.refresh_hotkeys(@hotkeys.labels)
      end

      # Validate a hotkey against keyboard gamepad mappings.
      # Combo hotkeys (Array) never conflict with plain key gamepad mappings.
      # @param hotkey [String, Array] plain keysym or modifier combo
      # @return [String, nil] error message if conflict, nil if ok
      def validate_hotkey(hotkey)
        return nil if hotkey.is_a?(Array)

        @kb_map.labels.each do |gba_btn, key|
          if key == hotkey
            return "\"#{hotkey}\" is mapped to GBA button #{gba_btn.upcase}"
          end
        end
        nil
      end

      # Validate a keyboard gamepad mapping against hotkeys.
      # Only plain-key hotkeys conflict — combo hotkeys (Ctrl+K) are fine.
      # @return [String, nil] error message if conflict, nil if ok
      def validate_kb_mapping(keysym)
        action = @hotkeys.action_for(keysym)
        if action
          label = action.to_s.tr('_', ' ').capitalize
          return "\"#{keysym}\" is assigned to hotkey: #{label}"
        end
        nil
      end

      # Verify config/saves/states directories are writable.
      # Shows a Tk dialog and aborts if any are not.
      def check_writable_dirs
        dirs = {
          'Config'      => Config.config_dir,
          'Saves'       => @config.saves_dir,
          'Save States' => Config.default_states_dir,
        }

        problems = []
        dirs.each do |label, dir|
          begin
            FileUtils.mkdir_p(dir)
          rescue SystemCallError => e
            problems << "#{label}: #{dir}\n  #{e.message}"
            next
          end
          unless File.writable?(dir)
            problems << "#{label}: #{dir}\n  Not writable"
          end
        end

        return if problems.empty?

        msg = "Cannot write to required directories:\n\n#{problems.join("\n\n")}\n\n" \
              "Check file permissions or set a custom path in config."
        @app.command(:tk_messageBox, icon: :error, type: :ok,
                     title: 'mGBA Player', message: msg)
        @app.destroy('.')
        exit 1
      end

      def start_gamepad_probe
        @app.after(GAMEPAD_PROBE_MS) { gamepad_probe_tick }
      end

      def gamepad_probe_tick
        return unless @running
        has_gp = @gamepad && !@gamepad.closed?
        settings_visible = @app.command(:wm, 'state', SettingsWindow::TOP) != 'withdrawn' rescue false

        # When settings is visible, use update_state (SDL_GameControllerUpdate)
        # instead of poll_events (SDL_PollEvent) to avoid pumping the Cocoa
        # run loop, which steals events from Tk's native widgets.
        # Background events hint ensures update_state gets fresh data even
        # when the SDL window doesn't have focus.
        if settings_visible && has_gp
          Teek::SDL2::Gamepad.update_state

          # Listen mode: capture first pressed button for remap
          if @settings_window.listening_for
            Teek::SDL2::Gamepad.buttons.each do |btn|
              if @gamepad.button?(btn)
                @settings_window.capture_mapping(btn)
                break
              end
            end
          end

          @app.after(GAMEPAD_LISTEN_MS) { gamepad_probe_tick }
          return
        end

        # Settings closed: use poll_events for hot-plug callbacks
        unless @core
          Teek::SDL2::Gamepad.poll_events rescue nil
        end
        @app.after(GAMEPAD_PROBE_MS) { gamepad_probe_tick }
      end

      def refresh_gamepads
        names = [translate('settings.keyboard_only')]
        prev_gp = @gamepad
        8.times do |i|
          gp = begin; Teek::SDL2::Gamepad.open(i); rescue; nil; end
          next unless gp
          names << gp.name
          @gamepad ||= gp
          gp.close unless gp == @gamepad
        end
        @settings_window&.update_gamepad_list(names)
        update_status_label
        if @gamepad && @gamepad != prev_gp
          @gp_map.device = @gamepad
          @gp_map.load_config
        end
      end

      def update_status_label
        return if @core # hidden during gameplay
        gp_text = @gamepad ? @gamepad.name : translate('settings.no_gamepad')
        @app.command(@status_label, :configure,
          text: "#{translate('player.open_rom_hint')}\n#{gp_text}")
      end

      def setup_input
        @viewport.bind('KeyPress', :keysym, '%s') do |k, state_str|
          if k == 'Escape'
            @fullscreen ? toggle_fullscreen : (@running = false)
          else
            mods = HotkeyMap.modifiers_from_state(state_str.to_i)
            case @hotkeys.action_for(k, modifiers: mods)
            when :quit          then @running = false
            when :pause         then toggle_pause
            when :fast_forward  then toggle_fast_forward
            when :fullscreen    then toggle_fullscreen
            when :show_fps      then toggle_show_fps
            when :quick_save    then quick_save
            when :quick_load    then quick_load
            when :save_states   then show_state_picker
            when :screenshot    then take_screenshot
            when :rewind        then do_rewind
            when :record        then toggle_recording
            else @keyboard.press(k)
            end
          end
        end

        @viewport.bind('KeyRelease', :keysym) do |k|
          @keyboard.release(k)
        end

        @viewport.bind('FocusIn')  { @has_focus = true }
        @viewport.bind('FocusOut') { @has_focus = false }

        # Alt+Return fullscreen toggle (emulator convention)
        @app.command(:bind, @viewport.frame.path, '<Alt-Return>', proc { toggle_fullscreen })
      end

      def build_menu
        menubar = '.menubar'
        @app.command(:menu, menubar)
        @app.command('.', :configure, menu: menubar)

        # File menu
        @app.command(:menu, "#{menubar}.file", tearoff: 0)
        @app.command(menubar, :add, :cascade, label: translate('menu.file'), menu: "#{menubar}.file")

        @app.command("#{menubar}.file", :add, :command,
                     label: translate('menu.open_rom'), accelerator: 'Cmd+O',
                     command: proc { open_rom_dialog })

        # Recent ROMs submenu
        @recent_menu = "#{menubar}.file.recent"
        @app.command(:menu, @recent_menu, tearoff: 0)
        @app.command("#{menubar}.file", :add, :cascade,
                     label: translate('menu.recent'), menu: @recent_menu)
        rebuild_recent_menu

        @app.command("#{menubar}.file", :add, :separator)
        @app.command("#{menubar}.file", :add, :command,
                     label: translate('menu.quit'), accelerator: 'Cmd+Q',
                     command: proc { @running = false })

        @app.command(:bind, '.', '<Command-o>', proc { open_rom_dialog })
        @app.command(:bind, '.', '<Command-comma>', proc { show_settings })

        # Settings menu — one entry per settings tab
        settings_menu = "#{menubar}.settings"
        @app.command(:menu, settings_menu, tearoff: 0)
        @app.command(menubar, :add, :cascade, label: translate('menu.settings'), menu: settings_menu)

        SettingsWindow::TABS.each do |locale_key, tab_path|
          display = translate(locale_key)
          accel = locale_key == 'settings.video' ? 'Cmd+,' : nil
          opts = { label: "#{display}…", command: proc { show_settings(tab: tab_path) } }
          opts[:accelerator] = accel if accel
          @app.command(settings_menu, :add, :command, **opts)
        end

        # View menu
        view_menu = "#{menubar}.view"
        @app.command(:menu, view_menu, tearoff: 0)
        @app.command(menubar, :add, :cascade, label: translate('menu.view'), menu: view_menu)

        @app.command(view_menu, :add, :command,
                     label: translate('menu.fullscreen'), accelerator: 'F11',
                     command: proc { toggle_fullscreen })
        @app.command(view_menu, :add, :command,
                     label: translate('menu.rom_info'), state: :disabled,
                     command: proc { show_rom_info })
        @view_menu = view_menu

        # Emulation menu
        @emu_menu = "#{menubar}.emu"
        @app.command(:menu, @emu_menu, tearoff: 0)
        @app.command(menubar, :add, :cascade, label: translate('menu.emulation'), menu: @emu_menu)

        @app.command(@emu_menu, :add, :command,
                     label: translate('menu.pause'), accelerator: 'P',
                     command: proc { toggle_pause })
        @app.command(@emu_menu, :add, :command,
                     label: translate('menu.reset'), accelerator: 'Cmd+R',
                     command: proc { reset_core })
        @app.command(@emu_menu, :add, :separator)
        @app.command(@emu_menu, :add, :command,
                     label: translate('menu.quick_save'), accelerator: 'F5', state: :disabled,
                     command: proc { quick_save })
        @app.command(@emu_menu, :add, :command,
                     label: translate('menu.quick_load'), accelerator: 'F8', state: :disabled,
                     command: proc { quick_load })
        @app.command(@emu_menu, :add, :separator)
        @app.command(@emu_menu, :add, :command,
                     label: translate('menu.save_states'), accelerator: 'F6', state: :disabled,
                     command: proc { show_state_picker })
        @app.command(@emu_menu, :add, :separator)
        @app.command(@emu_menu, :add, :command,
                     label: translate('menu.start_recording'), accelerator: 'F10', state: :disabled,
                     command: proc { toggle_recording })

        @app.command(:bind, '.', '<Command-r>', proc { reset_core })
      end

      def toggle_pause
        return unless @core
        @paused = !@paused
        if @paused
          @stream.clear
          @stream.pause
          @toast&.show(translate('toast.paused'), permanent: true)
          @app.command(@emu_menu, :entryconfigure, 0, label: translate('menu.resume'))
        else
          @toast&.destroy
          @stream.clear
          @audio_fade_in = FADE_IN_FRAMES
          @stream.resume
          @next_frame = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @app.command(@emu_menu, :entryconfigure, 0, label: translate('menu.pause'))
        end
      end

      def toggle_fast_forward
        return unless @core
        @fast_forward = !@fast_forward
        if @fast_forward
          @hud.set_ff_label(ff_label_text)
        else
          @hud.set_ff_label(nil)
          @next_frame = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @stream.clear
        end
      end

      def apply_turbo_speed(speed)
        @turbo_speed = speed
        @hud.set_ff_label(ff_label_text) if @fast_forward
      end

      def ff_label_text
        @turbo_speed == 0 ? translate('player.ff_max') : translate('player.ff', speed: @turbo_speed)
      end

      def apply_aspect_ratio(keep)
        @keep_aspect_ratio = keep
      end

      def toggle_fullscreen
        @fullscreen = !@fullscreen
        @app.command(:wm, 'attributes', '.', '-fullscreen', @fullscreen ? 1 : 0)
      end

      def apply_show_fps(show)
        @show_fps = show
        @hud.set_fps(nil) unless @show_fps
      end

      def apply_toast_duration(secs)
        @config.toast_duration = secs
        @toast.duration = secs
      end

      def apply_quick_slot(slot)
        @quick_save_slot = slot.to_i.clamp(1, 10)
        @save_mgr.quick_save_slot = @quick_save_slot if @save_mgr
      end

      def apply_backup(enabled)
        @save_state_backup = !!enabled
        @save_mgr.backup = @save_state_backup if @save_mgr
      end

      def open_config_dir
        dir = Config.config_dir
        FileUtils.mkdir_p(dir)
        p = Teek.platform
        if p.darwin?
          system('open', dir)
        elsif p.windows?
          system('explorer.exe', dir)
        else
          system('xdg-open', dir)
        end
      end

      def toggle_show_fps
        @show_fps = !@show_fps
        @hud.set_fps(nil) unless @show_fps
        @app.set_variable(SettingsWindow::VAR_SHOW_FPS, @show_fps ? '1' : '0')
      end

      # -- Recording -----------------------------------------------------------

      def toggle_recording
        return unless @core
        @recorder&.recording? ? stop_recording : start_recording
      end

      def start_recording
        dir = @config.recordings_dir
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S_%L')
        title = @core.title.strip.gsub(/[^a-zA-Z0-9_.-]/, '_')
        filename = "#{title}_#{timestamp}.trec"
        path = File.join(dir, filename)
        @recorder = Recorder.new(path, width: GBA_W, height: GBA_H,
                                 compression: @recording_compression)
        @recorder.start
        @toast&.show(translate('toast.recording_started'))
        update_recording_menu
      end

      def stop_recording
        return unless @recorder&.recording?
        @recorder.stop
        count = @recorder.frame_count
        @toast&.show(translate('toast.recording_stopped', frames: count))
        @recorder = nil
        update_recording_menu
      end

      # Capture current frame for recording. Reads audio_buffer (destructive)
      # and returns the raw PCM so the caller can pass it to queue_audio.
      # Returns nil when not recording.
      def capture_frame
        return nil unless @recorder&.recording?
        pcm = @core.audio_buffer
        @recorder.capture(@core.video_buffer_argb, pcm)
        pcm
      end

      def update_recording_menu
        label = @recorder&.recording? ? translate('menu.stop_recording') : translate('menu.start_recording')
        @app.command(@emu_menu, :entryconfigure, 8, label: label)
      end

      def apply_recording_compression(val)
        @recording_compression = val.to_i.clamp(1, 9)
      end

      def open_recordings_dir
        dir = @config.recordings_dir
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        p = Teek.platform
        if p.darwin?
          system('open', dir)
        elsif p.windows?
          system('explorer.exe', dir)
        else
          system('xdg-open', dir)
        end
      end

      # -- End recording -------------------------------------------------------

      def reset_core
        return unless @rom_path
        load_rom(@rom_path)
      end

      def confirm_rom_change(new_path)
        return true unless @core && !@core.destroyed?

        name = File.basename(new_path)
        result = @app.command('tk_messageBox',
          parent: '.',
          title: translate('dialog.game_running_title'),
          message: translate('dialog.game_running_msg', name: name),
          type: :okcancel,
          icon: :warning)
        result == 'ok'
      end

      def setup_drop_target
        @app.register_drop_target('.')
        @app.bind('.', '<<DropFile>>', :data) do |data|
          paths = @app.split_list(data)
          handle_dropped_files(paths)
        end
      end

      def handle_dropped_files(paths)
        if paths.length != 1
          @app.command('tk_messageBox',
            parent: '.',
            title: translate('dialog.drop_error_title'),
            message: translate('dialog.drop_single_file_only'),
            type: :ok,
            icon: :warning)
          return
        end

        path = paths.first
        ext = File.extname(path).downcase
        unless RomLoader::SUPPORTED_EXTENSIONS.include?(ext)
          @app.command('tk_messageBox',
            parent: '.',
            title: translate('dialog.drop_error_title'),
            message: translate('dialog.drop_unsupported_type', ext: ext),
            type: :ok,
            icon: :warning)
          return
        end

        return unless confirm_rom_change(path)
        load_rom(path)
      end

      def open_rom_dialog
        filetypes = '{{GBA ROMs} {.gba}} {{GB ROMs} {.gb .gbc}} {{ZIP Archives} {.zip}} {{All Files} {*}}'
        title = translate('menu.open_rom').delete('…')
        path = @app.tcl_eval("tk_getOpenFile -title {#{title}} -filetypes {#{filetypes}}")
        return if path.empty?
        return unless confirm_rom_change(path)

        load_rom(path)
      end

      def load_rom(path)
        # Menu callbacks (Open ROM, Recent) can fire before init_sdl2 because
        # macOS renders the menu bar at the OS level, outside tk busy's reach.
        # @stream is nil until init_sdl2; the ROM will load via @initial_rom.
        return unless @stream

        # Resolve ZIP archives to a bare ROM path
        rom_path = begin
          RomLoader.resolve(path)
        rescue RomLoader::NoRomInZip => e
          show_rom_error(translate('dialog.no_rom_in_zip', name: e.message))
          return
        rescue RomLoader::MultipleRomsInZip => e
          show_rom_error(translate('dialog.multiple_roms_in_zip', name: e.message))
          return
        rescue RomLoader::UnsupportedFormat => e
          show_rom_error(translate('dialog.drop_unsupported_type', ext: e.message))
          return
        rescue RomLoader::ZipReadError => e
          show_rom_error(translate('dialog.zip_read_error', detail: e.message))
          return
        end

        stop_recording if @recorder&.recording?

        if @core && !@core.destroyed?
          @core.destroy
        end
        @stream.clear

        saves = @config.saves_dir
        FileUtils.mkdir_p(saves) unless File.directory?(saves)
        @core = Core.new(rom_path, saves)
        @rom_path = path

        # Activate per-game config overlay (before reading settings)
        rom_id = Config.rom_id(@core.game_code, @core.checksum)
        @config.activate_game(rom_id)
        refresh_from_config
        @settings_window.set_per_game_available(true)
        @settings_window.set_per_game_active(@config.per_game_settings?)
        @save_mgr = SaveStateManager.new(core: @core, config: @config, app: @app)
        @save_mgr.state_dir = @save_mgr.state_dir_for_rom(@core)
        @save_mgr.quick_save_slot = @quick_save_slot
        @save_mgr.backup = @save_state_backup
        @core.rewind_init(@rewind_seconds) if @rewind_enabled
        @rewind_frame_counter = 0
        @paused = false
        @stream.resume
        @app.command(:place, :forget, @status_label) rescue nil
        @app.set_window_title("mGBA \u2014 #{@core.title}")
        @app.command(@view_menu, :entryconfigure, 1, state: :normal)
        # Enable save state + recording menu entries
        # Quick Save=3, Quick Load=4, Save States=6, Record=8
        [3, 4, 6, 8].each { |i| @app.command(@emu_menu, :entryconfigure, i, state: :normal) }
        @fps_count = 0
        @fps_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @next_frame = @fps_time
        @audio_samples_produced = 0

        @config.add_recent_rom(path)
        @config.save!
        rebuild_recent_menu

        sav_name = File.basename(path, File.extname(path)) + '.sav'
        sav_path = File.join(saves, sav_name)
        if File.exist?(sav_path)
          @toast&.show(translate('toast.loaded_sav', name: sav_name))
        else
          @toast&.show(translate('toast.created_sav', name: sav_name))
        end
      end

      def open_recent_rom(path)
        unless File.exist?(path)
          @app.command('tk_messageBox',
            parent: '.',
            title: translate('dialog.rom_not_found_title'),
            message: translate('dialog.rom_not_found_msg', path: path),
            type: :ok,
            icon: :error)
          @config.remove_recent_rom(path)
          @config.save!
          rebuild_recent_menu
          return
        end
        return unless confirm_rom_change(path)

        load_rom(path)
      end

      def rebuild_recent_menu
        # Clear all existing entries
        @app.command(@recent_menu, :delete, 0, :end) rescue nil

        roms = @config.recent_roms
        if roms.empty?
          @app.command(@recent_menu, :add, :command,
                       label: translate('player.none'), state: :disabled)
        else
          roms.each do |rom_path|
            label = File.basename(rom_path)
            @app.command(@recent_menu, :add, :command,
                         label: label,
                         command: proc { open_recent_rom(rom_path) })
          end
          @app.command(@recent_menu, :add, :separator)
          @app.command(@recent_menu, :add, :command,
                       label: translate('player.clear'),
                       command: proc { clear_recent_roms })
        end
      end

      def clear_recent_roms
        @config.clear_recent_roms
        @config.save!
        rebuild_recent_menu
      end

      def tick
        unless @core
          @viewport.render { |r| r.clear(0, 0, 0) }
          return
        end

        if @paused
          dest = compute_dest_rect
          @viewport.render do |r|
            r.clear(0, 0, 0)
            r.copy(@texture, nil, dest)
            if @recorder&.recording?
              rx = (dest ? dest[0] : 0) + 12
              ry = (dest ? dest[1] : 0) + 12
              r.fill_circle(rx, ry, 5, 220, 30, 30, 200)
            end
            @hud.draw(r, dest, show_fps: @show_fps)
            @toast&.draw(r, dest)
          end
          return
        end

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @next_frame ||= now

        if @fast_forward
          tick_fast_forward(now)
        else
          tick_normal(now)
        end
      end

      def tick_normal(now)
        frames = 0
        while @next_frame <= now && frames < 4
          run_one_frame
          rec_pcm = capture_frame
          queue_audio(raw_pcm: rec_pcm)

          # Dynamic rate control — proportional feedback on audio buffer fill.
          # Based on Near/byuu's algorithm for emulator A/V sync:
          #   https://docs.libretro.com/guides/ratecontrol.pdf
          #
          # fill  = how full the audio buffer is          (0.0 .. 1.0)
          # ratio = (1 - MAX_DELTA) + 2 * fill * MAX_DELTA
          #
          #   fill=0.0 (starving) → ratio=0.995 → shorter wait → emu speeds up
          #   fill=0.5 (target)   → ratio=1.000 → no change
          #   fill=1.0 (overfull) → ratio=1.005 → longer wait  → emu slows down
          #
          # The buffer naturally settles around 50% full. The ±0.5% limit
          # keeps pitch/speed shifts imperceptible.
          fill = (@stream.queued_samples.to_f / AUDIO_BUF_CAPACITY).clamp(0.0, 1.0)
          ratio = (1.0 - MAX_DELTA) + 2.0 * fill * MAX_DELTA
          @next_frame += FRAME_PERIOD * ratio
          frames += 1
        end

        @next_frame = now if now - @next_frame > 0.1
        return if frames == 0

        render_frame
        update_fps(frames, now)
      end

      def tick_fast_forward(now)
        if @turbo_speed == 0
          # Uncapped: poll input once per tick to avoid flooding the Cocoa
          # event loop (SDL_PollEvent pumps it), then blast through frames.
          keys = poll_input
          FF_MAX_FRAMES.times do |i|
            @core.set_keys(keys)
            @core.run_frame
            rec_pcm = capture_frame
            if i == 0
              queue_audio(volume_override: @turbo_volume, raw_pcm: rec_pcm)
            elsif !rec_pcm
              @core.audio_buffer  # discard when not recording
            end
          end
          @next_frame = now
          render_frame(ff_indicator: true)
          update_fps(FF_MAX_FRAMES, now)
          return
        end

        # Paced turbo (2x, 3x, 4x): run @turbo_speed frames per FRAME_PERIOD.
        # Same timing gate as tick_normal so 2x ≈ 120 fps, not 2000 fps.
        frames = 0
        while @next_frame <= now && frames < @turbo_speed * 4
          @turbo_speed.times do
            run_one_frame
            rec_pcm = capture_frame
            if frames == 0
              queue_audio(volume_override: @turbo_volume, raw_pcm: rec_pcm)
            elsif !rec_pcm
              @core.audio_buffer  # discard when not recording
            end
            frames += 1
          end
          @next_frame += FRAME_PERIOD
        end
        @next_frame = now if now - @next_frame > 0.1
        return if frames == 0

        render_frame(ff_indicator: true)
        update_fps(frames, now)
      end

      # Read keyboard + gamepad state, return combined bitmask.
      # Uses SDL_GameControllerUpdate (not SDL_PollEvent) to read gamepad
      # state without pumping the Cocoa event loop on macOS — SDL_PollEvent
      # steals NSKeyDown events from Tk, making quit/escape unresponsive.
      # Hot-plug detection is handled separately by start_gamepad_probe.
      def poll_input
        begin
          Teek::SDL2::Gamepad.update_state
        rescue StandardError
          @gamepad = nil
          @gp_map.device = nil
        end
        @kb_map.mask | @gp_map.mask
      end

      REWIND_PUSH_INTERVAL = 60  # ~1 second at GBA framerate

      def run_one_frame
        @core.set_keys(poll_input)
        @core.run_frame
        @total_frames += 1
        @running = false if @frame_limit && @total_frames >= @frame_limit
        if @rewind_enabled
          @rewind_frame_counter += 1
          if @rewind_frame_counter >= REWIND_PUSH_INTERVAL
            @core.rewind_push
            @rewind_frame_counter = 0
          end
        end
      end

      def queue_audio(volume_override: nil, raw_pcm: nil)
        pcm = raw_pcm || @core.audio_buffer
        return if pcm.empty?

        @audio_samples_produced += pcm.bytesize / 4
        if @muted
          @audio_fade_in = 0
        else
          vol = volume_override || @volume
          pcm = apply_volume_to_pcm(pcm, vol) if vol < 1.0
          if @audio_fade_in > 0
            pcm, @audio_fade_in = self.class.apply_fade_ramp(pcm, @audio_fade_in, FADE_IN_FRAMES)
          end
          @stream.queue(pcm)
        end
      end

      def render_frame(ff_indicator: false)
        pixels = @core.video_buffer_argb
        @texture.update(pixels)
        dest = compute_dest_rect
        @viewport.render do |r|
          r.clear(0, 0, 0)
          r.copy(@texture, nil, dest)
          if @recorder&.recording?
            rx = (dest ? dest[0] : 0) + 12
            ry = (dest ? dest[1] : 0) + 12
            r.fill_circle(rx, ry, 5, 220, 30, 30, 200)
          end
          @hud.draw(r, dest, show_fps: @show_fps, show_ff: ff_indicator)
          @toast&.draw(r, dest)
        end
      end

      # Calculate a centered destination rectangle that preserves the GBA's 3:2
      # aspect ratio within the current renderer output. Returns nil when
      # stretching is preferred (keep_aspect_ratio off).
      #
      # Example — fullscreen on a 1920x1080 (16:9) monitor:
      #   scale_x = 1920 / 240 = 8.0
      #   scale_y = 1080 / 160 = 6.75
      #   scale   = min(8.0, 6.75) = 6.75   (height is the constraint)
      #   dest    = [150, 0, 1620, 1080]     (pillarboxed: 150px black bars L+R)
      #
      # Example — fullscreen on a 2560x1600 (16:10) monitor:
      #   scale_x = 2560 / 240 ≈ 10.67
      #   scale_y = 1600 / 160 = 10.0
      #   scale   = 10.0
      #   dest    = [80, 0, 2400, 1600]      (pillarboxed: 80px bars L+R)
      def compute_dest_rect
        return nil unless @keep_aspect_ratio

        out_w, out_h = @viewport.renderer.output_size
        scale_x = out_w.to_f / GBA_W
        scale_y = out_h.to_f / GBA_H
        scale = [scale_x, scale_y].min
        scale = scale.floor if @integer_scale && scale >= 1.0

        dest_w = (GBA_W * scale).to_i
        dest_h = (GBA_H * scale).to_i
        dest_x = (out_w - dest_w) / 2
        dest_y = (out_h - dest_h) / 2

        [dest_x, dest_y, dest_w, dest_h]
      end

      def update_fps(frames, now)
        @fps_count += frames
        elapsed = now - @fps_time
        if elapsed >= 1.0
          fps = (@fps_count / elapsed).round(1)
          @hud.set_fps(translate('player.fps', fps: fps)) if @show_fps
          @audio_samples_produced = 0
          @fps_count = 0
          @fps_time = now
        end
      end

      def animate
        if @running
          tick
          delay = (@core && !@paused) ? 1 : 100
          @app.after(delay) { animate }
        else
          cleanup
          @app.command(:destroy, '.')
        end
      end

      # Apply software volume to int16 stereo PCM data.
      def apply_volume_to_pcm(pcm, gain = @volume)
        samples = pcm.unpack('s*')
        samples.map! { |s| (s * gain).round.clamp(-32768, 32767) }
        samples.pack('s*')
      end

      # Apply a linear fade-in ramp to int16 stereo PCM data.
      # Pure function: takes remaining/total counters, returns [pcm, new_remaining].
      # @param pcm [String] packed int16 stereo PCM
      # @param remaining [Integer] fade samples remaining (counts down to 0)
      # @param total [Integer] total fade length in samples
      # @return [Array(String, Integer)] modified PCM and updated remaining count
      def self.apply_fade_ramp(pcm, remaining, total)
        samples = pcm.unpack('s*')
        i = 0
        while i < samples.length && remaining > 0
          gain = 1.0 - (remaining.to_f / total)
          samples[i]     = (samples[i]     * gain).round.clamp(-32768, 32767)
          samples[i + 1] = (samples[i + 1] * gain).round.clamp(-32768, 32767) if i + 1 < samples.length
          remaining -= 1
          i += 2
        end
        [samples.pack('s*'), remaining]
      end

      def cleanup
        return if @cleaned_up
        @cleaned_up = true

        stop_recording if @recorder&.recording?
        @stream&.pause unless @stream&.destroyed?
        @hud&.destroy
        @toast&.destroy
        @overlay_font&.destroy unless @overlay_font&.destroyed?
        @stream&.destroy unless @stream&.destroyed?
        @texture&.destroy unless @texture&.destroyed?
        @core&.destroy unless @core&.destroyed?
        RomLoader.cleanup_temp
      end
    end
  end
end
