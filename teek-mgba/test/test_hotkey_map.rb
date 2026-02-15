# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "json"

# Minimal config stub for unit testing HotkeyMap without Tk or SDL2.
class MockHotkeyConfig
  attr_reader :hotkey_data, :saved_hotkeys

  def initialize(hotkey_data = {})
    @hotkey_data = hotkey_data
    @saved_hotkeys = {}
  end

  def hotkeys
    @hotkey_data
  end

  def set_hotkey(action, keysym)
    @saved_hotkeys[action.to_s] = keysym.to_s
  end

  def reload!
    # no-op for unit tests
  end
end

class TestHotkeyMap < Minitest::Test
  def setup
    require "teek/mgba/hotkey_map"
  end

  def make_map(hotkey_data = {})
    config = MockHotkeyConfig.new(hotkey_data)
    [Teek::MGBA::HotkeyMap.new(config), config]
  end

  # -- Defaults -------------------------------------------------------------

  def test_defaults_match_expected_keysyms
    map, = make_map
    assert_equal 'q', map.key_for(:quit)
    assert_equal 'p', map.key_for(:pause)
    assert_equal 'Tab', map.key_for(:fast_forward)
    assert_equal 'F11', map.key_for(:fullscreen)
    assert_equal 'F3', map.key_for(:show_fps)
    assert_equal 'F5', map.key_for(:quick_save)
    assert_equal 'F8', map.key_for(:quick_load)
    assert_equal 'F6', map.key_for(:save_states)
    assert_equal 'F9', map.key_for(:screenshot)
  end

  def test_all_actions_have_defaults
    map, = make_map
    Teek::MGBA::HotkeyMap::ACTIONS.each do |action|
      refute_nil map.key_for(action), "Missing default for #{action}"
    end
  end

  # -- Reverse lookup -------------------------------------------------------

  def test_action_for_returns_correct_action
    map, = make_map
    assert_equal :quit, map.action_for('q')
    assert_equal :pause, map.action_for('p')
    assert_equal :fast_forward, map.action_for('Tab')
    assert_equal :quick_save, map.action_for('F5')
  end

  def test_action_for_returns_nil_for_unknown_key
    map, = make_map
    assert_nil map.action_for('z')
    assert_nil map.action_for('unknown')
  end

  # -- Rebinding ------------------------------------------------------------

  def test_set_rebinds_action
    map, = make_map
    map.set(:quit, 'Escape')
    assert_equal 'Escape', map.key_for(:quit)
    assert_equal :quit, map.action_for('Escape')
  end

  def test_set_clears_conflict
    map, = make_map
    # 'p' is currently bound to :pause — rebind :quit to 'p'
    map.set(:quit, 'p')
    assert_equal 'p', map.key_for(:quit)
    assert_nil map.key_for(:pause), "Old action should be unbound"
  end

  def test_set_does_not_affect_other_bindings
    map, = make_map
    map.set(:quit, 'Escape')
    assert_equal 'p', map.key_for(:pause)
    assert_equal 'F5', map.key_for(:quick_save)
  end

  # -- Reset ----------------------------------------------------------------

  def test_reset_restores_defaults
    map, = make_map
    map.set(:quit, 'Escape')
    map.set(:pause, 'F12')
    map.reset!
    assert_equal 'q', map.key_for(:quit)
    assert_equal 'p', map.key_for(:pause)
  end

  # -- Config loading -------------------------------------------------------

  def test_load_config_applies_saved_bindings
    map, = make_map({ 'quit' => 'Escape', 'pause' => 'F12' })
    assert_equal 'Escape', map.key_for(:quit)
    assert_equal 'F12', map.key_for(:pause)
    # Unsaved actions keep defaults
    assert_equal 'Tab', map.key_for(:fast_forward)
  end

  def test_load_config_ignores_unknown_actions
    map, = make_map({ 'bogus' => 'F1' })
    assert_nil map.action_for('F1')
    assert_equal 'q', map.key_for(:quit)
  end

  def test_load_config_empty_uses_defaults
    map, = make_map({})
    assert_equal 'q', map.key_for(:quit)
  end

  # -- Save to config -------------------------------------------------------

  def test_save_to_config_writes_all_bindings
    map, config = make_map
    map.set(:quit, 'Escape')
    map.save_to_config
    assert_equal 'Escape', config.saved_hotkeys['quit']
    assert_equal 'p', config.saved_hotkeys['pause']
  end

  # -- Labels ---------------------------------------------------------------

  def test_labels_returns_copy
    map, = make_map
    labels = map.labels
    labels[:quit] = 'CHANGED'
    assert_equal 'q', map.key_for(:quit), "Modifying labels hash should not affect map"
  end

  def test_labels_reflects_current_state
    map, = make_map
    map.set(:quit, 'Escape')
    labels = map.labels
    assert_equal 'Escape', labels[:quit]
  end
end
