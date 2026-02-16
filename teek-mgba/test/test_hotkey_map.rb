# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "json"
require "set"

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

  def set_hotkey(action, hk)
    @saved_hotkeys[action.to_s] = hk
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

  def test_save_to_config_preserves_combo_arrays
    map, config = make_map
    map.set(:quit, ['Control', 'q'])
    map.save_to_config
    assert_equal ['Control', 'q'], config.saved_hotkeys['quit']
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

  # -- Modifier combo support -----------------------------------------------

  def test_set_combo_hotkey
    map, = make_map
    map.set(:quit, ['Control', 'q'])
    assert_equal ['Control', 'q'], map.key_for(:quit)
  end

  def test_action_for_combo_with_modifiers
    map, = make_map
    map.set(:quit, ['Control', 'q'])
    result = map.action_for('q', modifiers: Set.new(['Control']))
    assert_equal :quit, result
  end

  def test_action_for_combo_wrong_modifiers
    map, = make_map
    map.set(:quit, ['Control', 'q'])
    assert_nil map.action_for('q', modifiers: Set.new(['Shift']))
  end

  def test_action_for_combo_no_modifiers
    map, = make_map
    map.set(:quit, ['Control', 'q'])
    assert_nil map.action_for('q'), "Combo should not match without modifiers"
  end

  def test_action_for_plain_key_ignores_active_modifiers
    map, = make_map
    # 'p' (pause) is a plain key — should only match without modifiers
    assert_nil map.action_for('p', modifiers: Set.new(['Control']))
    assert_equal :pause, map.action_for('p')
  end

  def test_action_for_multi_modifier_combo
    map, = make_map
    map.set(:screenshot, ['Control', 'Shift', 's'])
    result = map.action_for('s', modifiers: Set.new(['Control', 'Shift']))
    assert_equal :screenshot, result
  end

  def test_action_for_multi_modifier_partial_match_fails
    map, = make_map
    map.set(:screenshot, ['Control', 'Shift', 's'])
    assert_nil map.action_for('s', modifiers: Set.new(['Control']))
  end

  def test_set_combo_clears_conflicting_combo
    map, = make_map
    map.set(:quit, ['Control', 'q'])
    map.set(:pause, ['Control', 'q'])
    assert_nil map.key_for(:quit), "Old combo should be unbound"
    assert_equal ['Control', 'q'], map.key_for(:pause)
  end

  def test_load_config_with_combo_array
    map, = make_map({ 'quit' => ['Control', 'q'] })
    assert_equal ['Control', 'q'], map.key_for(:quit)
    result = map.action_for('q', modifiers: Set.new(['Control']))
    assert_equal :quit, result
  end

  # -- normalize (class method) ---------------------------------------------

  def test_normalize_plain_string
    assert_equal 'F5', Teek::MGBA::HotkeyMap.normalize('F5')
  end

  def test_normalize_single_element_array
    assert_equal 'q', Teek::MGBA::HotkeyMap.normalize(['q'])
  end

  def test_normalize_sorts_modifiers_canonically
    result = Teek::MGBA::HotkeyMap.normalize(['Shift', 'Control', 's'])
    assert_equal ['Control', 'Shift', 's'], result
  end

  def test_normalize_preserves_correct_order
    result = Teek::MGBA::HotkeyMap.normalize(['Control', 'Shift', 's'])
    assert_equal ['Control', 'Shift', 's'], result
  end

  # -- display_name (class method) ------------------------------------------

  def test_display_name_plain_string
    assert_equal 'F5', Teek::MGBA::HotkeyMap.display_name('F5')
  end

  def test_display_name_combo
    result = Teek::MGBA::HotkeyMap.display_name(['Control', 'q'])
    assert_equal 'Ctrl+Q', result
  end

  def test_display_name_multi_modifier
    result = Teek::MGBA::HotkeyMap.display_name(['Control', 'Shift', 's'])
    assert_equal 'Ctrl+Shift+S', result
  end

  # -- modifier helpers (class methods) -------------------------------------

  def test_modifier_key_recognizes_modifiers
    assert Teek::MGBA::HotkeyMap.modifier_key?('Control_L')
    assert Teek::MGBA::HotkeyMap.modifier_key?('Shift_R')
    assert Teek::MGBA::HotkeyMap.modifier_key?('Alt_L')
    assert Teek::MGBA::HotkeyMap.modifier_key?('Meta_L')
    assert Teek::MGBA::HotkeyMap.modifier_key?('Super_R')
  end

  def test_modifier_key_rejects_non_modifiers
    refute Teek::MGBA::HotkeyMap.modifier_key?('a')
    refute Teek::MGBA::HotkeyMap.modifier_key?('F5')
    refute Teek::MGBA::HotkeyMap.modifier_key?('Return')
  end

  def test_normalize_modifier
    assert_equal 'Control', Teek::MGBA::HotkeyMap.normalize_modifier('Control_L')
    assert_equal 'Control', Teek::MGBA::HotkeyMap.normalize_modifier('Control_R')
    assert_equal 'Shift', Teek::MGBA::HotkeyMap.normalize_modifier('Shift_L')
    assert_equal 'Alt', Teek::MGBA::HotkeyMap.normalize_modifier('Alt_L')
    assert_equal 'Alt', Teek::MGBA::HotkeyMap.normalize_modifier('Meta_L')
    assert_nil Teek::MGBA::HotkeyMap.normalize_modifier('a')
  end

  def test_modifiers_from_state_empty
    result = Teek::MGBA::HotkeyMap.modifiers_from_state(0)
    assert_empty result
  end

  def test_modifiers_from_state_shift
    result = Teek::MGBA::HotkeyMap.modifiers_from_state(1)
    assert_equal Set.new(['Shift']), result
  end

  def test_modifiers_from_state_control
    result = Teek::MGBA::HotkeyMap.modifiers_from_state(4)
    assert_equal Set.new(['Control']), result
  end

  def test_modifiers_from_state_alt
    result = Teek::MGBA::HotkeyMap.modifiers_from_state(8)
    assert_equal Set.new(['Alt']), result
  end

  def test_modifiers_from_state_control_shift
    result = Teek::MGBA::HotkeyMap.modifiers_from_state(5) # 4|1
    assert_equal Set.new(['Control', 'Shift']), result
  end

  def test_action_for_empty_modifiers_set_matches_plain
    map, = make_map
    # Empty set should behave same as nil (match plain keys)
    assert_equal :pause, map.action_for('p', modifiers: Set.new)
  end

  # -- Rewind action ---------------------------------------------------------

  def test_rewind_in_actions
    assert_includes Teek::MGBA::HotkeyMap::ACTIONS, :rewind
  end

  def test_rewind_default_is_shift_tab
    map, = make_map
    assert_equal ['Shift', 'Tab'], map.key_for(:rewind)
  end

  def test_rewind_action_for_shift_tab
    map, = make_map
    result = map.action_for('Tab', modifiers: Set.new(['Shift']))
    assert_equal :rewind, result
  end

  def test_rewind_does_not_match_plain_tab
    map, = make_map
    # Plain Tab is fast_forward, not rewind
    assert_equal :fast_forward, map.action_for('Tab')
  end

  def test_iso_left_tab_normalized_to_rewind
    map, = make_map
    # Shift+Tab produces ISO_Left_Tab on many platforms
    result = map.action_for('ISO_Left_Tab', modifiers: Set.new(['Shift']))
    assert_equal :rewind, result
  end

  def test_normalize_keysym_iso_left_tab
    assert_equal 'Tab', Teek::MGBA::HotkeyMap.normalize_keysym('ISO_Left_Tab')
  end

  def test_normalize_keysym_uppercase_letter
    assert_equal 'q', Teek::MGBA::HotkeyMap.normalize_keysym('Q')
    assert_equal 's', Teek::MGBA::HotkeyMap.normalize_keysym('S')
    assert_equal 'a', Teek::MGBA::HotkeyMap.normalize_keysym('A')
  end

  def test_normalize_keysym_shifted_numbers
    assert_equal '1', Teek::MGBA::HotkeyMap.normalize_keysym('exclam')
    assert_equal '2', Teek::MGBA::HotkeyMap.normalize_keysym('at')
    assert_equal '0', Teek::MGBA::HotkeyMap.normalize_keysym('parenright')
  end

  def test_normalize_keysym_passthrough
    assert_equal 'q', Teek::MGBA::HotkeyMap.normalize_keysym('q')
    assert_equal 'F5', Teek::MGBA::HotkeyMap.normalize_keysym('F5')
    assert_equal 'Tab', Teek::MGBA::HotkeyMap.normalize_keysym('Tab')
  end

  def test_action_for_shift_uppercase_matches_plain_combo
    map, = make_map
    map.set(:screenshot, ['Shift', 's'])
    # Tk sends 'S' (uppercase) when Shift+s is pressed
    result = map.action_for('S', modifiers: Set.new(['Shift']))
    assert_equal :screenshot, result
  end

  # -- Record action ---------------------------------------------------------

  def test_record_in_actions
    assert_includes Teek::MGBA::HotkeyMap::ACTIONS, :record
  end

  def test_record_default_is_f10
    map, = make_map
    assert_equal 'F10', map.key_for(:record)
  end

  def test_record_dispatches_on_f10
    map, = make_map
    assert_equal :record, map.action_for('F10')
  end
end
