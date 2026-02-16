# frozen_string_literal: true

require_relative "child_window"
require_relative "hotkey_map"
require_relative "locale"
require_relative "tip_service"

module Teek
  module MGBA
    # Settings window for the mGBA Player.
    #
    # Opens a Toplevel with a ttk::notebook containing Video, Audio, and
    # Gamepad tabs. Closing the window hides it (withdraw) rather than
    # destroying it.
    #
    # Widget paths and Tcl variable names are exposed as constants so tests
    # can interact with the UI the same way a user would (set variable,
    # generate event, assert result).
    class SettingsWindow
      include ChildWindow
      include Locale::Translatable

      TOP = ".mgba_settings"
      NB  = "#{TOP}.nb"

      # Widget paths for test interaction
      SCALE_COMBO = "#{NB}.video.scale_row.scale_combo"
      TURBO_COMBO = "#{NB}.video.turbo_row.turbo_combo"
      ASPECT_CHECK = "#{NB}.video.aspect_row.aspect"
      SHOW_FPS_CHECK = "#{NB}.video.fps_row.fps_check"
      TOAST_COMBO = "#{NB}.video.toast_row.toast_combo"
      FILTER_COMBO = "#{NB}.video.filter_row.filter_combo"
      INTEGER_SCALE_CHECK = "#{NB}.video.intscale_row.intscale"
      COLOR_CORRECTION_CHECK = "#{NB}.video.colorcorr_row.colorcorr"
      FRAME_BLENDING_CHECK = "#{NB}.video.frameblend_row.frameblend"
      REWIND_CHECK = "#{NB}.video.rewind_row.rewind"
      VOLUME_SCALE = "#{NB}.audio.vol_row.vol_scale"
      MUTE_CHECK = "#{NB}.audio.mute_row.mute"

      # Gamepad tab widget paths
      GAMEPAD_TAB   = "#{NB}.gamepad"
      GAMEPAD_COMBO = "#{GAMEPAD_TAB}.gp_row.gp_combo"
      DEADZONE_SCALE = "#{GAMEPAD_TAB}.dz_row.dz_scale"
      GP_RESET_BTN   = "#{GAMEPAD_TAB}.btn_bar.reset_btn"
      GP_UNDO_BTN    = "#{GAMEPAD_TAB}.btn_bar.undo_btn"

      # GBA button widget paths (for remapping)
      GP_BTN_A      = "#{GAMEPAD_TAB}.row_a.btn"
      GP_BTN_B      = "#{GAMEPAD_TAB}.row_b.btn"
      GP_BTN_L      = "#{GAMEPAD_TAB}.row_l.btn"
      GP_BTN_R      = "#{GAMEPAD_TAB}.row_r.btn"
      GP_BTN_UP     = "#{GAMEPAD_TAB}.row_up.btn"
      GP_BTN_DOWN   = "#{GAMEPAD_TAB}.row_down.btn"
      GP_BTN_LEFT   = "#{GAMEPAD_TAB}.row_left.btn"
      GP_BTN_RIGHT  = "#{GAMEPAD_TAB}.row_right.btn"
      GP_BTN_START  = "#{GAMEPAD_TAB}.row_start.btn"
      GP_BTN_SELECT = "#{GAMEPAD_TAB}.row_select.btn"

      # Hotkeys tab widget paths
      HK_TAB         = "#{NB}.hotkeys"
      HK_UNDO_BTN    = "#{HK_TAB}.btn_bar.undo_btn"
      HK_RESET_BTN   = "#{HK_TAB}.btn_bar.reset_btn"

      # Action → widget path mapping for hotkey buttons
      HK_ACTIONS = {
        quit:        "#{HK_TAB}.row_quit.btn",
        pause:       "#{HK_TAB}.row_pause.btn",
        fast_forward: "#{HK_TAB}.row_fast_forward.btn",
        fullscreen:  "#{HK_TAB}.row_fullscreen.btn",
        show_fps:    "#{HK_TAB}.row_show_fps.btn",
        quick_save:  "#{HK_TAB}.row_quick_save.btn",
        quick_load:  "#{HK_TAB}.row_quick_load.btn",
        save_states: "#{HK_TAB}.row_save_states.btn",
        screenshot:  "#{HK_TAB}.row_screenshot.btn",
        rewind:      "#{HK_TAB}.row_rewind.btn",
        record:      "#{HK_TAB}.row_record.btn",
      }.freeze

      # Action → locale key mapping
      HK_LOCALE_KEYS = {
        quit: 'settings.hk_quit', pause: 'settings.hk_pause',
        fast_forward: 'settings.hk_fast_forward', fullscreen: 'settings.hk_fullscreen',
        show_fps: 'settings.hk_show_fps', quick_save: 'settings.hk_quick_save',
        quick_load: 'settings.hk_quick_load', save_states: 'settings.hk_save_states',
        screenshot: 'settings.hk_screenshot',
        rewind: 'settings.hk_rewind',
        record: 'settings.hk_record',
      }.freeze

      # GBA button → locale key mapping
      GP_LOCALE_KEYS = {
        a: 'settings.gp_a', b: 'settings.gp_b',
        l: 'settings.gp_l', r: 'settings.gp_r',
        up: 'settings.gp_up', down: 'settings.gp_down',
        left: 'settings.gp_left', right: 'settings.gp_right',
        start: 'settings.gp_start', select: 'settings.gp_select',
      }.freeze

      # Per-game settings bar (above notebook, shown/hidden based on active tab)
      PER_GAME_BAR   = "#{TOP}.per_game_bar"
      PER_GAME_CHECK = "#{PER_GAME_BAR}.check"

      # Recording tab widget paths
      REC_TAB              = "#{NB}.recording"
      REC_COMPRESSION_COMBO = "#{REC_TAB}.comp_row.comp_combo"
      REC_OPEN_DIR_BTN     = "#{REC_TAB}.dir_row.open_btn"

      # Save States tab widget paths
      SS_TAB         = "#{NB}.savestates"
      SS_SLOT_COMBO  = "#{SS_TAB}.slot_row.slot_combo"
      SS_BACKUP_CHECK = "#{SS_TAB}.backup_row.backup_check"
      SS_OPEN_DIR_BTN = "#{SS_TAB}.dir_row.open_btn"

      # Bottom bar
      SAVE_BTN = "#{TOP}.save_btn"

      # Tcl variable names
      VAR_PER_GAME = '::mgba_per_game'
      VAR_SCALE    = '::mgba_scale'
      VAR_TURBO    = '::mgba_turbo'
      VAR_VOLUME   = '::mgba_volume'
      VAR_MUTE     = '::mgba_mute'
      VAR_GAMEPAD  = '::mgba_gamepad'
      VAR_DEADZONE = '::mgba_deadzone'
      VAR_ASPECT_RATIO = '::mgba_aspect_ratio'
      VAR_SHOW_FPS = '::mgba_show_fps'
      VAR_TOAST_DURATION = '::mgba_toast_duration'
      VAR_FILTER   = '::mgba_filter'
      VAR_INTEGER_SCALE = '::mgba_integer_scale'
      VAR_COLOR_CORRECTION = '::mgba_color_correction'
      VAR_FRAME_BLENDING = '::mgba_frame_blending'
      VAR_REWIND_ENABLED = '::mgba_rewind_enabled'
      VAR_QUICK_SLOT     = '::mgba_quick_slot'
      VAR_SS_BACKUP      = '::mgba_ss_backup'
      VAR_REC_COMPRESSION = '::mgba_rec_compression'

      # GBA button → widget path mapping
      GBA_BUTTONS = {
        a: GP_BTN_A, b: GP_BTN_B,
        l: GP_BTN_L, r: GP_BTN_R,
        up: GP_BTN_UP, down: GP_BTN_DOWN,
        left: GP_BTN_LEFT, right: GP_BTN_RIGHT,
        start: GP_BTN_START, select: GP_BTN_SELECT,
      }.freeze

      # Default GBA → SDL gamepad mappings (display names)
      DEFAULT_GP_LABELS = {
        a: 'a', b: 'b',
        l: 'left_shoulder', r: 'right_shoulder',
        up: 'dpad_up', down: 'dpad_down',
        left: 'dpad_left', right: 'dpad_right',
        start: 'start', select: 'back',
      }.freeze

      # Default GBA → Tk keysym mappings (keyboard mode display names)
      DEFAULT_KB_LABELS = {
        a: 'z', b: 'x',
        l: 'a', r: 's',
        up: 'Up', down: 'Down',
        left: 'Left', right: 'Right',
        start: 'Return', select: 'BackSpace',
      }.freeze

      # @param app [Teek::App]
      # @param callbacks [Hash] :on_scale_change, :on_volume_change, :on_mute_change,
      #   :on_gamepad_map_change, :on_deadzone_change
      CALLBACK_DEFAULTS = {
        on_validate_hotkey:     ->(_) { nil },
        on_validate_kb_mapping: ->(_) { nil },
      }.freeze

      def initialize(app, callbacks: {}, tip_dismiss_ms: TipService::DEFAULT_DISMISS_MS)
        @app = app
        @callbacks = CALLBACK_DEFAULTS.merge(callbacks)
        @tip_dismiss_ms = tip_dismiss_ms
        @listening_for = nil
        @listen_timer = nil
        @keyboard_mode = true
        @per_game_enabled = false
        @gp_labels = DEFAULT_KB_LABELS.dup
        @hk_listening_for = nil
        @hk_listen_timer = nil
        @hk_labels = HotkeyMap::DEFAULTS.dup
        @hk_pending_modifiers = Set.new
        @hk_mod_timer = nil

        build_toplevel(translate('menu.settings'), geometry: '700x560') { setup_ui }
      end

      # @return [Symbol, nil] the GBA button currently listening for remap, or nil
      attr_reader :listening_for

      # @return [Boolean] true when editing keyboard bindings, false for gamepad
      def keyboard_mode?
        @keyboard_mode
      end

      # @param tab [String, nil] widget path of the tab to select (e.g. SS_TAB)
      def show(tab: nil)
        @app.command(NB, 'select', tab) if tab
        show_window
      end

      # Tab widget paths keyed by locale key (caller uses translate to get display name)
      TABS = {
        'settings.video'       => "#{NB}.video",
        'settings.audio'       => "#{NB}.audio",
        'settings.gamepad'     => GAMEPAD_TAB,
        'settings.hotkeys'     => HK_TAB,
        'settings.recording'   => REC_TAB,
        'settings.save_states' => SS_TAB,
      }.freeze

      # Tabs that show the per-game settings checkbox
      PER_GAME_TABS = Set.new(["#{NB}.video", "#{NB}.audio", SS_TAB]).freeze

      def hide
        @tips&.hide
        hide_window
      end

      def update_gamepad_list(names)
        @app.command(GAMEPAD_COMBO, 'configure',
          values: Teek.make_list(*names))
        current = @app.get_variable(VAR_GAMEPAD)
        unless names.include?(current)
          @app.set_variable(VAR_GAMEPAD, names.first)
        end
      end

      # Enable the Save button (called when any setting changes)
      def mark_dirty
        @app.command(SAVE_BTN, 'configure', state: :normal)
      end

      # Enable/disable the per-game checkbox (called when ROM loads/unloads).
      def set_per_game_available(enabled)
        @per_game_enabled = enabled
        current = @app.command(NB, 'select') rescue nil
        if enabled && PER_GAME_TABS.include?(current)
          @app.command(PER_GAME_CHECK, 'configure', state: :normal)
        else
          @app.command(PER_GAME_CHECK, 'configure', state: :disabled)
        end
      end

      # Sync the per-game checkbox to the current config state.
      def set_per_game_active(active)
        @app.set_variable(VAR_PER_GAME, active ? '1' : '0')
      end

      private

      def do_save
        @callbacks[:on_save]&.call
        @app.command(SAVE_BTN, 'configure', state: :disabled)
      end

      def update_per_game_bar
        current = @app.command(NB, 'select')
        if PER_GAME_TABS.include?(current)
          @app.command(PER_GAME_CHECK, 'configure', state: @per_game_enabled ? :normal : :disabled)
        else
          @app.command(PER_GAME_CHECK, 'configure', state: :disabled)
        end
      end

      def setup_ui
        # Bold button style for customized mappings
        @app.tcl_eval("ttk::style configure Bold.TButton -font [list {*}[font actual TkDefaultFont] -weight bold]")

        @tips = TipService.new(@app, parent: TOP, dismiss_ms: @tip_dismiss_ms)

        # Per-game settings bar (above notebook, initially hidden)
        @app.command('ttk::frame', PER_GAME_BAR)
        @app.set_variable(VAR_PER_GAME, '0')
        @app.command('ttk::checkbutton', PER_GAME_CHECK,
          text: translate('settings.per_game'),
          variable: VAR_PER_GAME,
          state: :disabled,
          command: proc { |*|
            enabled = @app.get_variable(VAR_PER_GAME) == '1'
            @callbacks[:on_per_game_toggle]&.call(enabled)
            mark_dirty
          })
        @app.command(:pack, PER_GAME_CHECK, side: :left, padx: 5)

        per_game_tip = "#{PER_GAME_BAR}.tip"
        @app.command('ttk::label', per_game_tip, text: '(?)')
        @app.command(:pack, per_game_tip, side: :left)
        @tips.register(per_game_tip, translate('settings.tip_per_game'))

        @app.command('ttk::notebook', NB)
        @app.command(:pack, NB, fill: :both, expand: 1, padx: 5, pady: [5, 0])

        setup_video_tab
        setup_audio_tab
        setup_gamepad_tab
        setup_hotkeys_tab
        setup_recording_tab
        setup_save_states_tab

        # Show/hide per-game bar based on active tab
        @app.command(:bind, NB, '<<NotebookTabChanged>>', proc { update_per_game_bar })
        # Show bar initially (video tab is default)
        @app.command(:pack, PER_GAME_BAR, fill: :x, padx: 5, pady: [5, 0], before: NB)

        # Save button — disabled until a setting changes
        @app.command('ttk::button', SAVE_BTN, text: translate('settings.save'), state: :disabled,
          command: proc { do_save })
        @app.command(:pack, SAVE_BTN, side: :bottom, pady: [0, 8])
      end

      def setup_video_tab
        frame = "#{NB}.video"
        @app.command('ttk::frame', frame)
        @app.command(NB, 'add', frame, text: translate('settings.video'))

        # Window Scale
        row = "#{frame}.scale_row"
        @app.command('ttk::frame', row)
        @app.command(:pack, row, fill: :x, padx: 10, pady: [15, 5])

        @app.command('ttk::label', "#{row}.lbl", text: translate('settings.window_scale'))
        @app.command(:pack, "#{row}.lbl", side: :left)

        @app.set_variable(VAR_SCALE, '3x')
        @app.command('ttk::combobox', SCALE_COMBO,
          textvariable: VAR_SCALE,
          values: Teek.make_list('1x', '2x', '3x', '4x'),
          state: :readonly,
          width: 5)
        @app.command(:pack, SCALE_COMBO, side: :right)

        @app.command(:bind, SCALE_COMBO, '<<ComboboxSelected>>',
          proc { |*|
            val = @app.get_variable(VAR_SCALE)
            scale = val.to_i
            if scale > 0
              @callbacks[:on_scale_change]&.call(scale)
              mark_dirty
            end
          })

        # Turbo Speed
        turbo_row = "#{frame}.turbo_row"
        @app.command('ttk::frame', turbo_row)
        @app.command(:pack, turbo_row, fill: :x, padx: 10, pady: 5)

        @app.command('ttk::label', "#{turbo_row}.lbl", text: translate('settings.turbo_speed'))
        @app.command(:pack, "#{turbo_row}.lbl", side: :left)
        @tips.register("#{turbo_row}.lbl", translate('settings.tip_turbo_speed'))

        @app.set_variable(VAR_TURBO, '2x')
        @app.command('ttk::combobox', TURBO_COMBO,
          textvariable: VAR_TURBO,
          values: Teek.make_list('2x', '3x', '4x', translate('settings.uncapped')),
          state: :readonly,
          width: 10)
        @app.command(:pack, TURBO_COMBO, side: :right)

        @app.command(:bind, TURBO_COMBO, '<<ComboboxSelected>>',
          proc { |*|
            val = @app.get_variable(VAR_TURBO)
            speed = val == translate('settings.uncapped') ? 0 : val.to_i
            @callbacks[:on_turbo_speed_change]&.call(speed)
            mark_dirty
          })

        # Aspect ratio checkbox
        aspect_row = "#{frame}.aspect_row"
        @app.command('ttk::frame', aspect_row)
        @app.command(:pack, aspect_row, fill: :x, padx: 10, pady: 5)

        @app.set_variable(VAR_ASPECT_RATIO, '1')
        @app.command('ttk::checkbutton', ASPECT_CHECK,
          text: translate('settings.maintain_aspect'),
          variable: VAR_ASPECT_RATIO,
          command: proc { |*|
            keep = @app.get_variable(VAR_ASPECT_RATIO) == '1'
            @callbacks[:on_aspect_ratio_change]&.call(keep)
            mark_dirty
          })
        @app.command(:pack, ASPECT_CHECK, side: :left)

        # Show FPS checkbox
        fps_row = "#{frame}.fps_row"
        @app.command('ttk::frame', fps_row)
        @app.command(:pack, fps_row, fill: :x, padx: 10, pady: 5)

        @app.set_variable(VAR_SHOW_FPS, '1')
        @app.command('ttk::checkbutton', SHOW_FPS_CHECK,
          text: translate('settings.show_fps'),
          variable: VAR_SHOW_FPS,
          command: proc { |*|
            show = @app.get_variable(VAR_SHOW_FPS) == '1'
            @callbacks[:on_show_fps_change]&.call(show)
            mark_dirty
          })
        @app.command(:pack, SHOW_FPS_CHECK, side: :left)

        # Toast duration
        toast_row = "#{frame}.toast_row"
        @app.command('ttk::frame', toast_row)
        @app.command(:pack, toast_row, fill: :x, padx: 10, pady: 5)

        @app.command('ttk::label', "#{toast_row}.lbl", text: translate('settings.toast_duration'))
        @app.command(:pack, "#{toast_row}.lbl", side: :left)
        @tips.register("#{toast_row}.lbl", translate('settings.tip_toast_duration'))

        @app.set_variable(VAR_TOAST_DURATION, '1.5s')
        @app.command('ttk::combobox', TOAST_COMBO,
          textvariable: VAR_TOAST_DURATION,
          values: Teek.make_list('0.5s', '1s', '1.5s', '2s', '3s', '5s', '10s'),
          state: :readonly,
          width: 5)
        @app.command(:pack, TOAST_COMBO, side: :right)

        @app.command(:bind, TOAST_COMBO, '<<ComboboxSelected>>',
          proc { |*|
            val = @app.get_variable(VAR_TOAST_DURATION)
            secs = val.to_f
            if secs > 0
              @callbacks[:on_toast_duration_change]&.call(secs)
              mark_dirty
            end
          })

        # Pixel Filter
        filter_row = "#{frame}.filter_row"
        @app.command('ttk::frame', filter_row)
        @app.command(:pack, filter_row, fill: :x, padx: 10, pady: 5)

        @app.command('ttk::label', "#{filter_row}.lbl", text: translate('settings.pixel_filter'))
        @app.command(:pack, "#{filter_row}.lbl", side: :left)
        @tips.register("#{filter_row}.lbl", translate('settings.tip_pixel_filter'))

        @app.set_variable(VAR_FILTER, translate('settings.filter_nearest'))
        @app.command('ttk::combobox', FILTER_COMBO,
          textvariable: VAR_FILTER,
          values: Teek.make_list(translate('settings.filter_nearest'), translate('settings.filter_linear')),
          state: :readonly,
          width: 18)
        @app.command(:pack, FILTER_COMBO, side: :right)

        @app.command(:bind, FILTER_COMBO, '<<ComboboxSelected>>',
          proc { |*|
            val = @app.get_variable(VAR_FILTER)
            filter = val == translate('settings.filter_nearest') ? 'nearest' : 'linear'
            @callbacks[:on_filter_change]&.call(filter)
            mark_dirty
          })

        # Integer scaling checkbox
        intscale_row = "#{frame}.intscale_row"
        @app.command('ttk::frame', intscale_row)
        @app.command(:pack, intscale_row, fill: :x, padx: 10, pady: 5)

        @app.set_variable(VAR_INTEGER_SCALE, '0')
        @app.command('ttk::checkbutton', INTEGER_SCALE_CHECK,
          text: translate('settings.integer_scale'),
          variable: VAR_INTEGER_SCALE,
          command: proc { |*|
            enabled = @app.get_variable(VAR_INTEGER_SCALE) == '1'
            @callbacks[:on_integer_scale_change]&.call(enabled)
            mark_dirty
          })
        @app.command(:pack, INTEGER_SCALE_CHECK, side: :left)
        intscale_tip = "#{intscale_row}.tip"
        @app.command('ttk::label', intscale_tip, text: '(?)')
        @app.command(:pack, intscale_tip, side: :left)
        @tips.register(intscale_tip, translate('settings.tip_integer_scale'))

        # Color correction checkbox
        colorcorr_row = "#{frame}.colorcorr_row"
        @app.command('ttk::frame', colorcorr_row)
        @app.command(:pack, colorcorr_row, fill: :x, padx: 10, pady: 5)

        @app.set_variable(VAR_COLOR_CORRECTION, '0')
        @app.command('ttk::checkbutton', COLOR_CORRECTION_CHECK,
          text: translate('settings.color_correction'),
          variable: VAR_COLOR_CORRECTION,
          command: proc { |*|
            enabled = @app.get_variable(VAR_COLOR_CORRECTION) == '1'
            @callbacks[:on_color_correction_change]&.call(enabled)
            mark_dirty
          })
        @app.command(:pack, COLOR_CORRECTION_CHECK, side: :left)
        colorcorr_tip = "#{colorcorr_row}.tip"
        @app.command('ttk::label', colorcorr_tip, text: '(?)')
        @app.command(:pack, colorcorr_tip, side: :left)
        @tips.register(colorcorr_tip, translate('settings.tip_color_correction'))

        # Frame blending checkbox
        frameblend_row = "#{frame}.frameblend_row"
        @app.command('ttk::frame', frameblend_row)
        @app.command(:pack, frameblend_row, fill: :x, padx: 10, pady: 5)

        @app.set_variable(VAR_FRAME_BLENDING, '0')
        @app.command('ttk::checkbutton', FRAME_BLENDING_CHECK,
          text: translate('settings.frame_blending'),
          variable: VAR_FRAME_BLENDING,
          command: proc { |*|
            enabled = @app.get_variable(VAR_FRAME_BLENDING) == '1'
            @callbacks[:on_frame_blending_change]&.call(enabled)
            mark_dirty
          })
        @app.command(:pack, FRAME_BLENDING_CHECK, side: :left)
        frameblend_tip = "#{frameblend_row}.tip"
        @app.command('ttk::label', frameblend_tip, text: '(?)')
        @app.command(:pack, frameblend_tip, side: :left)
        @tips.register(frameblend_tip, translate('settings.tip_frame_blending'))

        # Rewind checkbox
        rewind_row = "#{frame}.rewind_row"
        @app.command('ttk::frame', rewind_row)
        @app.command(:pack, rewind_row, fill: :x, padx: 10, pady: 5)

        @app.set_variable(VAR_REWIND_ENABLED, '1')
        @app.command('ttk::checkbutton', REWIND_CHECK,
          text: translate('settings.rewind'),
          variable: VAR_REWIND_ENABLED,
          command: proc { |*|
            enabled = @app.get_variable(VAR_REWIND_ENABLED) == '1'
            @callbacks[:on_rewind_toggle]&.call(enabled)
            mark_dirty
          })
        @app.command(:pack, REWIND_CHECK, side: :left)
        rewind_tip = "#{rewind_row}.tip"
        @app.command('ttk::label', rewind_tip, text: '(?)')
        @app.command(:pack, rewind_tip, side: :left)
        @tips.register(rewind_tip, translate('settings.tip_rewind'))
      end

      def setup_audio_tab
        frame = "#{NB}.audio"
        @app.command('ttk::frame', frame)
        @app.command(NB, 'add', frame, text: translate('settings.audio'))

        # Volume slider
        vol_row = "#{frame}.vol_row"
        @app.command('ttk::frame', vol_row)
        @app.command(:pack, vol_row, fill: :x, padx: 10, pady: [15, 5])

        @app.command('ttk::label', "#{vol_row}.lbl", text: translate('settings.volume'))
        @app.command(:pack, "#{vol_row}.lbl", side: :left)

        @vol_val_label = "#{vol_row}.vol_label"
        @app.command('ttk::label', @vol_val_label, text: '100%', width: 5)
        @app.command(:pack, @vol_val_label, side: :right)

        @app.set_variable(VAR_VOLUME, '100')
        @app.command('ttk::scale', VOLUME_SCALE,
          orient: :horizontal,
          from: 0,
          to: 100,
          length: 150,
          variable: VAR_VOLUME,
          command: proc { |v, *|
            pct = v.to_f.round
            @app.command(@vol_val_label, 'configure', text: "#{pct}%")
            @callbacks[:on_volume_change]&.call(pct / 100.0)
            mark_dirty
          })
        @app.command(:pack, VOLUME_SCALE, side: :right, padx: [5, 5])

        # Mute checkbox
        mute_row = "#{frame}.mute_row"
        @app.command('ttk::frame', mute_row)
        @app.command(:pack, mute_row, fill: :x, padx: 10, pady: 5)

        @app.set_variable(VAR_MUTE, '0')
        @app.command('ttk::checkbutton', MUTE_CHECK,
          text: translate('settings.mute'),
          variable: VAR_MUTE,
          command: proc { |*|
            muted = @app.get_variable(VAR_MUTE) == '1'
            @callbacks[:on_mute_change]&.call(muted)
            mark_dirty
          })
        @app.command(:pack, MUTE_CHECK, side: :left)
      end
      def setup_gamepad_tab
        frame = GAMEPAD_TAB
        @app.command('ttk::frame', frame)
        @app.command(NB, 'add', frame, text: translate('settings.gamepad'))

        # Gamepad selector row
        gp_row = "#{frame}.gp_row"
        @app.command('ttk::frame', gp_row)
        @app.command(:pack, gp_row, fill: :x, padx: 10, pady: [8, 4])

        @app.command('ttk::label', "#{gp_row}.lbl", text: translate('settings.gamepad') + ':')
        @app.command(:pack, "#{gp_row}.lbl", side: :left)

        @app.set_variable(VAR_GAMEPAD, translate('settings.keyboard_only'))
        @app.command('ttk::combobox', GAMEPAD_COMBO,
          textvariable: VAR_GAMEPAD, state: :readonly, width: 20)
        @app.command(:pack, GAMEPAD_COMBO, side: :left, padx: 4)
        @app.command(GAMEPAD_COMBO, 'configure',
          values: Teek.make_list(translate('settings.keyboard_only')))

        @app.command(:bind, GAMEPAD_COMBO, '<<ComboboxSelected>>',
          proc { |*| switch_input_mode })

        # GBA button rows (vertical list, matching hotkeys tab style)
        GBA_BUTTONS.each do |gba_btn, btn_path|
          row = "#{frame}.row_#{gba_btn}"
          @app.command('ttk::frame', row)
          @app.command(:pack, row, fill: :x, padx: 10, pady: 2)

          lbl_path = "#{row}.lbl"
          @app.command('ttk::label', lbl_path, text: translate(GP_LOCALE_KEYS[gba_btn]), width: 14, anchor: :w)
          @app.command(:pack, lbl_path, side: :left)

          @app.command('ttk::button', btn_path, text: btn_display(gba_btn), width: 12,
            style: gp_customized?(gba_btn) ? 'Bold.TButton' : 'TButton',
            command: proc { start_listening(gba_btn) })
          @app.command(:pack, btn_path, side: :right)
        end

        # Bottom bar: Undo (left) | Reset to Defaults (right)
        btn_bar = "#{frame}.btn_bar"
        @app.command('ttk::frame', btn_bar)
        @app.command(:pack, btn_bar, fill: :x, side: :bottom, padx: 10, pady: [4, 8])

        @app.command('ttk::button', GP_UNDO_BTN, text: translate('settings.undo'),
          state: :disabled, command: proc { do_undo_gamepad })
        @app.command(:pack, GP_UNDO_BTN, side: :left)

        @app.command('ttk::button', GP_RESET_BTN, text: translate('settings.reset_defaults'),
          command: proc { confirm_reset_gamepad })
        @app.command(:pack, GP_RESET_BTN, side: :right)

        # Dead zone slider (disabled in keyboard mode)
        dz_row = "#{frame}.dz_row"
        @app.command('ttk::frame', dz_row)
        @app.command(:pack, dz_row, fill: :x, padx: 10, pady: [4, 8], side: :bottom)

        @app.command('ttk::label', "#{dz_row}.lbl", text: translate('settings.dead_zone'))
        @app.command(:pack, "#{dz_row}.lbl", side: :left)
        @tips.register("#{dz_row}.lbl", translate('settings.tip_dead_zone'))

        @dz_val_label = "#{dz_row}.dz_label"
        @app.command('ttk::label', @dz_val_label, text: '25%', width: 5)
        @app.command(:pack, @dz_val_label, side: :right)

        @app.set_variable(VAR_DEADZONE, '25')
        @app.command('ttk::scale', DEADZONE_SCALE,
          orient: :horizontal, from: 0, to: 50, length: 150,
          variable: VAR_DEADZONE,
          command: proc { |v, *|
            pct = v.to_f.round
            @app.command(@dz_val_label, 'configure', text: "#{pct}%")
            threshold = (pct / 100.0 * 32767).round
            @callbacks[:on_deadzone_change]&.call(threshold)
            mark_dirty
          })
        @app.command(:pack, DEADZONE_SCALE, side: :right, padx: [5, 5])

        # Start in keyboard mode — dead zone disabled
        set_deadzone_enabled(false)
      end

      def setup_hotkeys_tab
        frame = HK_TAB
        @app.command('ttk::frame', frame)
        @app.command(NB, 'add', frame, text: translate('settings.hotkeys'))

        # Scrollable list of action rows
        HK_ACTIONS.each do |action, btn_path|
          row = "#{frame}.row_#{action}"
          @app.command('ttk::frame', row)
          @app.command(:pack, row, fill: :x, padx: 10, pady: 2)

          lbl_path = "#{row}.lbl"
          @app.command('ttk::label', lbl_path, text: translate(HK_LOCALE_KEYS[action]), width: 14, anchor: :w)
          @app.command(:pack, lbl_path, side: :left)

          display = hk_display(action)
          @app.command('ttk::button', btn_path, text: display, width: 12,
            style: hk_customized?(action) ? 'Bold.TButton' : 'TButton',
            command: proc { start_hk_listening(action) })
          @app.command(:pack, btn_path, side: :right)
        end

        # Bottom bar: Undo (left) | Reset to Defaults (right)
        btn_bar = "#{frame}.btn_bar"
        @app.command('ttk::frame', btn_bar)
        @app.command(:pack, btn_bar, fill: :x, side: :bottom, padx: 10, pady: [4, 8])

        @app.command('ttk::button', HK_UNDO_BTN, text: translate('settings.undo'),
          state: :disabled, command: proc { do_undo_hotkeys })
        @app.command(:pack, HK_UNDO_BTN, side: :left)

        @app.command('ttk::button', HK_RESET_BTN, text: translate('settings.hk_reset_defaults'),
          command: proc { confirm_reset_hotkeys })
        @app.command(:pack, HK_RESET_BTN, side: :right)
      end

      def setup_recording_tab
        frame = REC_TAB
        @app.command('ttk::frame', frame)
        @app.command(NB, 'add', frame, text: translate('settings.recording'))

        # Compression level
        comp_row = "#{frame}.comp_row"
        @app.command('ttk::frame', comp_row)
        @app.command(:pack, comp_row, fill: :x, padx: 10, pady: [15, 5])

        @app.command('ttk::label', "#{comp_row}.lbl", text: translate('settings.recording_compression'))
        @app.command(:pack, "#{comp_row}.lbl", side: :left)

        comp_tip = "#{comp_row}.tip"
        @app.command('ttk::label', comp_tip, text: '(?)')
        @app.command(:pack, comp_tip, side: :left)
        @tips.register(comp_tip, translate('settings.tip_recording_compression'))

        comp_values = (1..9).map(&:to_s)
        @app.set_variable(VAR_REC_COMPRESSION, '1')
        @app.command('ttk::combobox', REC_COMPRESSION_COMBO,
          textvariable: VAR_REC_COMPRESSION,
          values: Teek.make_list(*comp_values),
          state: :readonly,
          width: 5)
        @app.command(:pack, REC_COMPRESSION_COMBO, side: :right)

        @app.command(:bind, REC_COMPRESSION_COMBO, '<<ComboboxSelected>>',
          proc { |*|
            val = @app.get_variable(VAR_REC_COMPRESSION).to_i
            if val >= 1 && val <= 9
              @callbacks[:on_compression_change]&.call(val)
              mark_dirty
            end
          })

        # Open Recordings Folder button
        dir_row = "#{frame}.dir_row"
        @app.command('ttk::frame', dir_row)
        @app.command(:pack, dir_row, fill: :x, padx: 10, pady: [15, 5])

        @app.command('ttk::button', REC_OPEN_DIR_BTN,
          text: translate('settings.open_recordings_folder'),
          command: proc { @callbacks[:on_open_recordings_dir]&.call })
        @app.command(:pack, REC_OPEN_DIR_BTN, side: :left)
      end

      def setup_save_states_tab
        frame = SS_TAB
        @app.command('ttk::frame', frame)
        @app.command(NB, 'add', frame, text: translate('settings.save_states'))

        # Quick Save Slot
        slot_row = "#{frame}.slot_row"
        @app.command('ttk::frame', slot_row)
        @app.command(:pack, slot_row, fill: :x, padx: 10, pady: [15, 5])

        @app.command('ttk::label', "#{slot_row}.lbl", text: translate('settings.quick_save_slot'))
        @app.command(:pack, "#{slot_row}.lbl", side: :left)

        slot_values = (1..10).map(&:to_s)
        @app.set_variable(VAR_QUICK_SLOT, '1')
        @app.command('ttk::combobox', SS_SLOT_COMBO,
          textvariable: VAR_QUICK_SLOT,
          values: Teek.make_list(*slot_values),
          state: :readonly,
          width: 5)
        @app.command(:pack, SS_SLOT_COMBO, side: :right)

        @app.command(:bind, SS_SLOT_COMBO, '<<ComboboxSelected>>',
          proc { |*|
            val = @app.get_variable(VAR_QUICK_SLOT).to_i
            if val >= 1 && val <= 10
              @callbacks[:on_quick_slot_change]&.call(val)
              mark_dirty
            end
          })

        # Backup rotation checkbox
        backup_row = "#{frame}.backup_row"
        @app.command('ttk::frame', backup_row)
        @app.command(:pack, backup_row, fill: :x, padx: 10, pady: 5)

        @app.set_variable(VAR_SS_BACKUP, '1')
        @app.command('ttk::checkbutton', SS_BACKUP_CHECK,
          text: translate('settings.keep_backup'),
          variable: VAR_SS_BACKUP,
          command: proc { |*|
            enabled = @app.get_variable(VAR_SS_BACKUP) == '1'
            @callbacks[:on_backup_change]&.call(enabled)
            mark_dirty
          })
        @app.command(:pack, SS_BACKUP_CHECK, side: :left)
        backup_tip = "#{backup_row}.tip"
        @app.command('ttk::label', backup_tip, text: '(?)')
        @app.command(:pack, backup_tip, side: :left)
        @tips.register(backup_tip, translate('settings.tip_keep_backup'))

        # Open Config Folder button
        dir_row = "#{frame}.dir_row"
        @app.command('ttk::frame', dir_row)
        @app.command(:pack, dir_row, fill: :x, padx: 10, pady: [15, 5])

        @app.command('ttk::button', SS_OPEN_DIR_BTN,
          text: translate('settings.open_config_folder'),
          command: proc { @callbacks[:on_open_config_dir]&.call })
        @app.command(:pack, SS_OPEN_DIR_BTN, side: :left)
      end

      KEY_DISPLAY_LOCALE = {
        'Up' => 'settings.key_up', 'Down' => 'settings.key_down',
        'Left' => 'settings.key_left', 'Right' => 'settings.key_right',
      }.freeze

      def btn_display(gba_btn)
        label = @gp_labels[gba_btn] || '?'
        locale_key = KEY_DISPLAY_LOCALE[label]
        locale_key ? translate(locale_key) : label
      end

      def gp_customized?(gba_btn)
        defaults = @keyboard_mode ? DEFAULT_KB_LABELS : DEFAULT_GP_LABELS
        @gp_labels[gba_btn] != defaults[gba_btn]
      end

      def hk_customized?(action)
        @hk_labels[action] != HotkeyMap::DEFAULTS[action]
      end

      # Display-friendly text for a hotkey button.
      def hk_display(action)
        val = @hk_labels[action]
        return '?' unless val
        HotkeyMap.display_name(val)
      end

      # Update a mapping button's text and bold style.
      def style_btn(widget, text, bold)
        @app.command(widget, 'configure', text: text, style: bold ? 'Bold.TButton' : 'TButton')
      end

      def confirm_reset_gamepad
        cancel_listening
        confirmed = if @callbacks[:on_confirm_reset_gamepad]
          @callbacks[:on_confirm_reset_gamepad].call
        else
          @app.command('tk_messageBox',
            parent: TOP,
            title: translate('dialog.reset_gamepad_title'),
            message: translate('dialog.reset_gamepad_msg'),
            type: :yesno,
            icon: :question) == 'yes'
        end
        if confirmed
          reset_gamepad_defaults
          do_save
        end
      end

      def reset_gamepad_defaults
        @gp_labels = (@keyboard_mode ? DEFAULT_KB_LABELS : DEFAULT_GP_LABELS).dup
        GBA_BUTTONS.each do |gba_btn, widget|
          style_btn(widget, btn_display(gba_btn), false)
        end
        @app.command(DEADZONE_SCALE, 'set', 25) unless @keyboard_mode
        @app.command(GP_UNDO_BTN, 'configure', state: :disabled)
        if @keyboard_mode
          @callbacks[:on_keyboard_reset]&.call
        else
          @callbacks[:on_gamepad_reset]&.call
        end
      end

      def do_undo_gamepad
        @callbacks[:on_undo_gamepad]&.call
        @app.command(GP_UNDO_BTN, 'configure', state: :disabled)
      end

      def switch_input_mode
        cancel_listening
        selected = @app.get_variable(VAR_GAMEPAD)
        @keyboard_mode = (selected == translate('settings.keyboard_only'))

        if @keyboard_mode
          @gp_labels = DEFAULT_KB_LABELS.dup
          set_deadzone_enabled(false)
        else
          @gp_labels = DEFAULT_GP_LABELS.dup
          set_deadzone_enabled(true)
        end

        GBA_BUTTONS.each do |gba_btn, widget|
          style_btn(widget, btn_display(gba_btn), false)
        end

        @app.command(GP_UNDO_BTN, 'configure', state: :disabled)
        @callbacks[:on_input_mode_change]&.call(@keyboard_mode, selected)
      end

      def set_deadzone_enabled(enabled)
        state = enabled ? :normal : :disabled
        @app.command(DEADZONE_SCALE, 'configure', state: state)
      end

      LISTEN_TIMEOUT_MS = 10_000
      MODIFIER_SETTLE_MS = 600

      def start_listening(gba_btn)
        cancel_listening
        @listening_for = gba_btn
        widget = GBA_BUTTONS[gba_btn]
        @app.command(widget, 'configure', text: translate('settings.press'))
        @listen_timer = @app.after(LISTEN_TIMEOUT_MS) { cancel_listening }

        if @keyboard_mode
          # Use tcl_eval directly because Teek's command() wraps each arg in
          # braces, which breaks Tk event substitutions like %K in bind scripts.
          cb_id = @app.interp.register_callback(
            proc { |keysym, *| capture_mapping(keysym) })
          @app.tcl_eval("bind #{TOP} <Key> {ruby_callback #{cb_id} %K}")
        end
      end

      def cancel_listening
        if @listen_timer
          @app.command(:after, :cancel, @listen_timer)
          @listen_timer = nil
        end
        if @listening_for
          unbind_keyboard_listen
          widget = GBA_BUTTONS[@listening_for]
          style_btn(widget, btn_display(@listening_for), gp_customized?(@listening_for))
          @listening_for = nil
        end
      end

      def unbind_keyboard_listen
        @app.tcl_eval("bind #{TOP} <Key> {}")
      end

      # Called by the player's poll loop when a gamepad button is detected
      # during listen mode.
      public

      # Refresh the gamepad tab widgets from external state (e.g. after undo).
      # @param labels [Hash{Symbol => String}] GBA button → gamepad button name
      # @param dead_zone [Integer] dead zone percentage (0-50)
      def refresh_gamepad(labels, dead_zone)
        @gp_labels = labels.dup
        GBA_BUTTONS.each do |gba_btn, widget|
          style_btn(widget, btn_display(gba_btn), gp_customized?(gba_btn))
        end
        @app.command(DEADZONE_SCALE, 'set', dead_zone)
      end

      def capture_mapping(button)
        return unless @listening_for

        # In keyboard mode, reject keys that conflict with hotkeys
        if @keyboard_mode
          error = @callbacks[:on_validate_kb_mapping].call(button.to_s)
          if error
            show_key_conflict(error)
            cancel_listening
            return
          end
        end

        if @listen_timer
          @app.command(:after, :cancel, @listen_timer)
          @listen_timer = nil
        end
        unbind_keyboard_listen

        gba_btn = @listening_for
        @gp_labels[gba_btn] = button.to_s
        widget = GBA_BUTTONS[gba_btn]
        style_btn(widget, btn_display(gba_btn), gp_customized?(gba_btn))
        @listening_for = nil

        if @keyboard_mode
          @callbacks[:on_keyboard_map_change]&.call(gba_btn, button)
        else
          @callbacks[:on_gamepad_map_change]&.call(gba_btn, button)
        end
        @app.command(GP_UNDO_BTN, 'configure', state: :normal)
        mark_dirty
      end

      # Refresh the hotkeys tab widgets from external state (e.g. after undo).
      # @param labels [Hash{Symbol => String}] action → keysym
      def refresh_hotkeys(labels)
        @hk_labels = labels.dup
        HK_ACTIONS.each do |action, widget|
          style_btn(widget, hk_display(action), hk_customized?(action))
        end
      end

      # @return [Symbol, nil] the hotkey action currently listening for remap
      attr_reader :hk_listening_for

      # Capture a hotkey during listen mode. Called by the Tk <Key>
      # bind script, or directly by tests.
      #
      # Modifier keys (Ctrl, Shift, Alt) start a pending combo — if a
      # non-modifier key follows within MODIFIER_SETTLE_MS, the combo is
      # captured. If the timer expires, the modifier alone is captured.
      #
      # @param keysym [String] Tk keysym (e.g. "Control_L", "k")
      def capture_hk_mapping(keysym)
        return unless @hk_listening_for

        mod = HotkeyMap.normalize_modifier(keysym)
        if mod
          # Modifier pressed — accumulate and wait for a non-modifier key
          @hk_pending_modifiers << mod
          cancel_mod_timer
          @hk_mod_timer = @app.after(MODIFIER_SETTLE_MS) { finalize_hk(keysym) }
          return
        end

        # Non-modifier key arrived — normalize variant keysyms
        # (e.g. Shift+Tab produces ISO_Left_Tab on many platforms)
        keysym = HotkeyMap.normalize_keysym(keysym)
        cancel_mod_timer
        if @hk_pending_modifiers.any?
          hotkey = [*@hk_pending_modifiers.sort_by { |m| HotkeyMap::MODIFIER_ORDER.index(m) || 99 }, keysym]
          @hk_pending_modifiers.clear
        else
          hotkey = keysym
        end

        finalize_hk(hotkey)
      end

      # Finalize a captured hotkey (plain key or combo). Also called by
      # tests that want to bypass the modifier settle timer.
      # @param hotkey [String, Array]
      def finalize_hk(hotkey)
        return unless @hk_listening_for
        cancel_mod_timer
        @hk_pending_modifiers.clear

        hotkey = HotkeyMap.normalize(hotkey)

        # Reject hotkeys that conflict with keyboard gamepad mappings
        # (only plain keys can conflict — combos with modifiers are fine)
        unless hotkey.is_a?(Array)
          error = @callbacks[:on_validate_hotkey].call(hotkey.to_s)
          if error
            show_key_conflict(error)
            cancel_hk_listening
            return
          end
        end

        if @hk_listen_timer
          @app.command(:after, :cancel, @hk_listen_timer)
          @hk_listen_timer = nil
        end
        unbind_keyboard_listen

        action = @hk_listening_for
        @hk_labels[action] = hotkey
        widget = HK_ACTIONS[action]
        style_btn(widget, hk_display(action), hk_customized?(action))
        @hk_listening_for = nil

        @callbacks[:on_hotkey_change]&.call(action, hotkey)
        @app.command(HK_UNDO_BTN, 'configure', state: :normal)
        mark_dirty
      end

      private

      def start_hk_listening(action)
        cancel_hk_listening
        @hk_listening_for = action
        widget = HK_ACTIONS[action]
        @app.command(widget, 'configure', text: translate('settings.press'))
        @hk_listen_timer = @app.after(LISTEN_TIMEOUT_MS) { cancel_hk_listening }

        cb_id = @app.interp.register_callback(
          proc { |keysym, *| capture_hk_mapping(keysym) })
        @app.tcl_eval("bind #{TOP} <Key> {ruby_callback #{cb_id} %K}")
      end

      def cancel_hk_listening
        cancel_mod_timer
        @hk_pending_modifiers.clear
        if @hk_listen_timer
          @app.command(:after, :cancel, @hk_listen_timer)
          @hk_listen_timer = nil
        end
        if @hk_listening_for
          unbind_keyboard_listen
          widget = HK_ACTIONS[@hk_listening_for]
          style_btn(widget, hk_display(@hk_listening_for), hk_customized?(@hk_listening_for))
          @hk_listening_for = nil
        end
      end

      def cancel_mod_timer
        if @hk_mod_timer
          @app.command(:after, :cancel, @hk_mod_timer)
          @hk_mod_timer = nil
        end
      end

      def show_key_conflict(message)
        if @callbacks[:on_key_conflict]
          @callbacks[:on_key_conflict].call(message)
        else
          @app.command('tk_messageBox',
            parent: TOP,
            title: translate('dialog.key_conflict_title'),
            message: message,
            type: :ok,
            icon: :warning)
        end
      end

      def do_undo_hotkeys
        @callbacks[:on_undo_hotkeys]&.call
        @app.command(HK_UNDO_BTN, 'configure', state: :disabled)
      end

      def confirm_reset_hotkeys
        cancel_hk_listening
        confirmed = if @callbacks[:on_confirm_reset_hotkeys]
          @callbacks[:on_confirm_reset_hotkeys].call
        else
          @app.command('tk_messageBox',
            parent: TOP,
            title: translate('dialog.reset_hotkeys_title'),
            message: translate('dialog.reset_hotkeys_msg'),
            type: :yesno,
            icon: :question) == 'yes'
        end
        if confirmed
          reset_hotkey_defaults
          do_save
        end
      end

      def reset_hotkey_defaults
        cancel_hk_listening
        @hk_labels = HotkeyMap::DEFAULTS.dup
        HK_ACTIONS.each do |action, widget|
          style_btn(widget, hk_display(action), false)
        end
        @app.command(HK_UNDO_BTN, 'configure', state: :disabled)
        @callbacks[:on_hotkey_reset]&.call
      end

    end
  end
end
