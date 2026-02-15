# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test/tk_test_helper"

class TestMGBASettingsHotkeys < Minitest::Test
  include TeekTestHelper

  def test_hotkeys_tab_exists
    assert_tk_app("hotkeys tab exists in notebook") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      tabs = app.command(Teek::MGBA::SettingsWindow::NB, 'tabs')
      assert_includes tabs, Teek::MGBA::SettingsWindow::HK_TAB
    end
  end

  def test_hotkey_buttons_show_default_keysyms
    assert_tk_app("hotkey buttons show default keysyms") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'cget', '-text')
      assert_equal 'q', text
      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:pause], 'cget', '-text')
      assert_equal 'p', text
      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quick_save], 'cget', '-text')
      assert_equal 'F5', text
      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:screenshot], 'cget', '-text')
      assert_equal 'F9', text
    end
  end

  def test_clicking_hotkey_button_enters_listen_mode
    assert_tk_app("clicking hotkey button enters listen mode") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'invoke')
      app.update

      assert_equal :quit, sw.hk_listening_for
      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'cget', '-text')
      assert_equal "Press\u2026", text
    end
  end

  def test_capture_updates_label_and_fires_callback
    assert_tk_app("capturing hotkey updates label and fires callback") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      received_action = nil
      received_key = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_hotkey_change: proc { |a, k| received_action = a; received_key = k }
      })
      sw.show
      app.update

      # Click to start listening for quit hotkey
      app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'invoke')
      app.update

      # Simulate key capture
      sw.capture_hk_mapping('Escape')
      app.update

      assert_nil sw.hk_listening_for
      assert_equal :quit, received_action
      assert_equal 'Escape', received_key
      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'cget', '-text')
      assert_equal 'Escape', text
    end
  end

  def test_capture_enables_undo_button
    assert_tk_app("capturing hotkey enables undo button") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      # Initially disabled
      state = app.command(Teek::MGBA::SettingsWindow::HK_UNDO_BTN, 'cget', '-state')
      assert_equal 'disabled', state

      # Rebind
      app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:pause], 'invoke')
      app.update
      sw.capture_hk_mapping('F12')
      app.update

      state = app.command(Teek::MGBA::SettingsWindow::HK_UNDO_BTN, 'cget', '-state')
      assert_equal 'normal', state
    end
  end

  def test_undo_fires_callback_and_disables
    assert_tk_app("undo fires on_undo_hotkeys and disables button") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      undo_called = false
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_undo_hotkeys: proc { undo_called = true }
      })
      sw.show
      app.update

      # Rebind to enable undo
      app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'invoke')
      app.update
      sw.capture_hk_mapping('Escape')
      app.update

      # Click undo
      app.command(Teek::MGBA::SettingsWindow::HK_UNDO_BTN, 'invoke')
      app.update

      assert undo_called
      state = app.command(Teek::MGBA::SettingsWindow::HK_UNDO_BTN, 'cget', '-state')
      assert_equal 'disabled', state
    end
  end

  def test_reset_restores_defaults
    assert_tk_app("reset restores default hotkey labels") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      reset_called = false
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_hotkey_reset: proc { reset_called = true },
        on_confirm_reset_hotkeys: -> { true },
      })
      sw.show
      app.update

      # Rebind quit
      app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'invoke')
      app.update
      sw.capture_hk_mapping('Escape')
      app.update

      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'cget', '-text')
      assert_equal 'Escape', text

      # Click Reset to Defaults
      app.command(Teek::MGBA::SettingsWindow::HK_RESET_BTN, 'invoke')
      app.update

      assert reset_called
      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'cget', '-text')
      assert_equal 'q', text
      state = app.command(Teek::MGBA::SettingsWindow::HK_UNDO_BTN, 'cget', '-state')
      assert_equal 'disabled', state
    end
  end

  def test_refresh_hotkeys_updates_labels
    assert_tk_app("refresh_hotkeys updates button labels") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      new_labels = Teek::MGBA::HotkeyMap::DEFAULTS.merge(quit: 'Escape', pause: 'F12')
      sw.refresh_hotkeys(new_labels)
      app.update

      assert_equal 'Escape', app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'cget', '-text')
      assert_equal 'F12', app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:pause], 'cget', '-text')
      # Unchanged bindings stay the same
      assert_equal 'Tab', app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:fast_forward], 'cget', '-text')
    end
  end

  def test_cancel_listen_restores_label
    assert_tk_app("canceling listen restores original label") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      # Enter listen for quit
      app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'invoke')
      app.update
      assert_equal :quit, sw.hk_listening_for

      # Start listening for a different one — cancels the first
      app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:pause], 'invoke')
      app.update

      assert_equal :pause, sw.hk_listening_for
      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'cget', '-text')
      assert_equal 'q', text, "Original quit label should be restored"
    end
  end

  def test_capture_without_listen_is_noop
    assert_tk_app("capture without listen mode is a no-op") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      received = false
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_hotkey_change: proc { |*| received = true }
      })
      sw.show
      app.update

      # Capture without entering listen mode
      sw.capture_hk_mapping('F12')
      app.update

      refute received
      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'cget', '-text')
      assert_equal 'q', text, "Label should be unchanged"
    end
  end

  # -- Conflict validation ---------------------------------------------------

  def test_hotkey_rejected_when_conflicting_with_gamepad_key
    assert_tk_app("hotkey rejected when key conflicts with gamepad mapping") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      received = false
      conflict_msg = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_hotkey_change: proc { |*| received = true },
        on_validate_hotkey: ->(keysym) {
          # Simulate: 'z' is GBA button A
          keysym == 'z' ? '"z" is mapped to GBA button A' : nil
        },
        on_key_conflict: proc { |msg| conflict_msg = msg },
      })
      sw.show
      app.update

      # Try to bind quit to 'z' (conflicts with GBA A)
      app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'invoke')
      app.update
      sw.capture_hk_mapping('z')
      app.update

      refute received, "on_hotkey_change should not fire for rejected key"
      assert_equal '"z" is mapped to GBA button A', conflict_msg
      # Label should revert to original, not show 'z'
      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'cget', '-text')
      assert_equal 'q', text
      assert_nil sw.hk_listening_for
    end
  end

  def test_hotkey_accepted_when_no_conflict
    assert_tk_app("hotkey accepted when no conflict") do
      require "teek/mgba/settings_window"
      require "teek/mgba/hotkey_map"
      received_action = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_hotkey_change: proc { |a, _| received_action = a },
        on_validate_hotkey: ->(_) { nil },
      })
      sw.show
      app.update

      app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'invoke')
      app.update
      sw.capture_hk_mapping('F12')
      app.update

      assert_equal :quit, received_action
      text = app.command(Teek::MGBA::SettingsWindow::HK_ACTIONS[:quit], 'cget', '-text')
      assert_equal 'F12', text
    end
  end
end
