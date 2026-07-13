# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/keysyms'

class TestKeysyms < Minitest::Test
  def test_resolve_a_friendly_symbol_has_no_modifiers
    modifiers, keysym = Teek::UI::Keysyms.resolve(:enter)

    assert_equal [], modifiers
    assert_equal 'Return', keysym
  end

  def test_resolve_covers_the_common_named_keys
    {
      escape: 'Escape', tab: 'Tab', space: 'space', backspace: 'BackSpace',
      delete: 'Delete', up: 'Up', down: 'Down', left: 'Left', right: 'Right',
      f1: 'F1', f12: 'F12',
    }.each do |friendly, tk_keysym|
      _, keysym = Teek::UI::Keysyms.resolve(friendly)
      assert_equal tk_keysym, keysym, "#{friendly.inspect} should resolve to #{tk_keysym}"
    end
  end

  def test_resolve_an_unknown_symbol_passes_through_as_the_literal_keysym
    _, keysym = Teek::UI::Keysyms.resolve(:q)

    assert_equal 'q', keysym
  end

  def test_resolve_a_single_modifier_string
    modifiers, keysym = Teek::UI::Keysyms.resolve('Ctrl-s')

    assert_equal ['Control'], modifiers
    assert_equal 's', keysym
  end

  def test_resolve_a_multi_modifier_string
    modifiers, keysym = Teek::UI::Keysyms.resolve('Ctrl-Shift-s')

    assert_equal %w[Control Shift], modifiers
    assert_equal 's', keysym
  end

  def test_resolve_a_modifier_string_with_a_friendly_base_key
    modifiers, keysym = Teek::UI::Keysyms.resolve('Ctrl-Enter')

    assert_equal ['Control'], modifiers
    assert_equal 'Return', keysym
  end

  def test_patterns_for_the_common_case_is_a_single_pattern
    patterns = Teek::UI::Keysyms.patterns_for(['Control'], 's')

    assert_equal ['<Control-s>'], patterns
  end

  def test_patterns_for_no_modifiers
    patterns = Teek::UI::Keysyms.patterns_for([], 'Return')

    assert_equal ['<Return>'], patterns
  end

  def test_patterns_for_shift_tab_covers_the_iso_left_tab_gotcha
    patterns = Teek::UI::Keysyms.patterns_for(['Shift'], 'Tab')

    assert_includes patterns, '<Shift-Tab>'
    assert_includes patterns, '<ISO_Left_Tab>'
  end

  def test_patterns_for_plain_tab_is_unaffected_by_the_shift_tab_special_case
    patterns = Teek::UI::Keysyms.patterns_for([], 'Tab')

    assert_equal ['<Tab>'], patterns
  end
end
