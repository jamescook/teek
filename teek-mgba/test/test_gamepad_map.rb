# frozen_string_literal: true

require "minitest/autorun"
require "teek_mgba"
require_relative "../../teek-mgba/lib/teek/mgba/config"
require_relative "../../teek-mgba/lib/teek/mgba/input_mappings"
require_relative "support/input_mocks"

class TestGamepadMap < Minitest::Test
  def setup
    @config = MockInputConfig.new
    @map = Teek::MGBA::GamepadMap.new(@config)
  end

  def test_default_labels
    labels = @map.labels
    assert_equal 'a', labels[:a]
    assert_equal 'b', labels[:b]
    assert_equal 'start', labels[:start]
  end

  def test_set_remap
    @map.set(:a, :y)
    assert_equal 'y', @map.labels[:a]
  end

  def test_set_removes_old_binding
    @map.set(:a, :y)
    refute @map.labels.values.include?('a')
  end

  def test_reset
    @map.set(:a, :y)
    @map.set_dead_zone(12000)
    @map.reset!
    assert_equal 'a', @map.labels[:a]
    assert_equal Teek::MGBA::GamepadMap::DEFAULT_DEAD_ZONE, @map.dead_zone
  end

  def test_mask_no_device
    assert_equal 0, @map.mask
  end

  def test_mask_with_device
    gp = MockGamepad.new
    @map.device = gp
    gp.buttons_pressed.add(:a)
    mask = @map.mask
    assert_equal Teek::MGBA::KEY_A, mask & Teek::MGBA::KEY_A
  end

  def test_mask_closed_device
    gp = MockGamepad.new
    @map.device = gp
    gp.buttons_pressed.add(:a)
    gp.close!
    assert_equal 0, @map.mask
  end

  def test_supports_deadzone
    assert @map.supports_deadzone?
  end

  def test_set_dead_zone
    @map.set_dead_zone(12000)
    assert_equal 12000, @map.dead_zone
  end

  def test_dead_zone_pct
    @map.set_dead_zone(16384)
    assert_equal 50, @map.dead_zone_pct
  end

  def test_load_config
    gp = MockGamepad.new
    @map.device = gp
    @map.load_config
    assert_equal 'x', @map.labels[:a]
    assert_equal 'y', @map.labels[:b]
    assert_equal (15 / 100.0 * 32767).round, @map.dead_zone
  end

  def test_load_config_no_device
    @map.load_config
    assert_equal 'a', @map.labels[:a]
  end

  def test_reload
    gp = MockGamepad.new
    @map.device = gp
    @map.set(:a, :y)
    @map.reload!
    assert @config.calls.any? { |c| c[0] == :reload! }
    assert_equal 'x', @map.labels[:a]
  end

  def test_save_to_config
    gp = MockGamepad.new(guid: 'test-guid', name: 'Test Pad')
    @map.device = gp
    @map.save_to_config
    gp_calls = @config.calls.select { |c| c[0] == :gamepad }
    assert_equal 1, gp_calls.size
    assert_equal 'test-guid', gp_calls[0][1]

    dz_calls = @config.calls.select { |c| c[0] == :set_dead_zone }
    assert_equal 1, dz_calls.size

    set_calls = @config.calls.select { |c| c[0] == :set_mapping }
    assert_equal 10, set_calls.size
  end

  def test_save_to_config_no_device
    @map.save_to_config
    assert_empty @config.calls.select { |c| c[0] == :set_mapping }
  end
end
