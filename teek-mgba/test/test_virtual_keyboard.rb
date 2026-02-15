# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../teek-mgba/lib/teek/mgba/input_mappings"

class TestVirtualKeyboard < Minitest::Test
  def setup
    @kb = Teek::MGBA::VirtualKeyboard.new
  end

  def test_button_false_initially
    refute @kb.button?('z')
  end

  def test_press_makes_button_true
    @kb.press('z')
    assert @kb.button?('z')
  end

  def test_release_makes_button_false
    @kb.press('z')
    @kb.release('z')
    refute @kb.button?('z')
  end

  def test_multiple_keys
    @kb.press('z')
    @kb.press('x')
    assert @kb.button?('z')
    assert @kb.button?('x')
    @kb.release('z')
    refute @kb.button?('z')
    assert @kb.button?('x')
  end

  def test_never_closed
    refute @kb.closed?
  end
end
