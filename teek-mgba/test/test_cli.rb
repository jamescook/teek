# frozen_string_literal: true

require "minitest/autorun"
require "teek_mgba"
require_relative "../../teek-mgba/lib/teek/mgba/version"
require_relative "../../teek-mgba/lib/teek/mgba/cli"

class TestCLI < Minitest::Test
  def parse(args)
    Teek::MGBA::CLI.parse(args)
  end

  # -- ROM argument --

  def test_rom_path
    opts = parse(["game.gba"])
    assert_equal "game.gba", opts[:rom]
  end

  def test_no_rom
    opts = parse([])
    assert_nil opts[:rom]
  end

  # -- flags --

  def test_scale
    opts = parse(["--scale", "2"])
    assert_equal 2, opts[:scale]
  end

  def test_scale_short
    opts = parse(["-s", "3"])
    assert_equal 3, opts[:scale]
  end

  def test_scale_clamps_high
    opts = parse(["--scale", "10"])
    assert_equal 4, opts[:scale]
  end

  def test_scale_clamps_low
    opts = parse(["--scale", "0"])
    assert_equal 1, opts[:scale]
  end

  def test_volume
    opts = parse(["--volume", "50"])
    assert_equal 50, opts[:volume]
  end

  def test_volume_short
    opts = parse(["-v", "75"])
    assert_equal 75, opts[:volume]
  end

  def test_volume_clamps
    opts = parse(["--volume", "200"])
    assert_equal 100, opts[:volume]
  end

  def test_mute
    opts = parse(["--mute"])
    assert opts[:mute]
  end

  def test_mute_short
    opts = parse(["-m"])
    assert opts[:mute]
  end

  def test_no_sound
    opts = parse(["--no-sound"])
    assert_equal false, opts[:sound]
  end

  def test_fullscreen
    opts = parse(["--fullscreen"])
    assert opts[:fullscreen]
  end

  def test_fullscreen_short
    opts = parse(["-f"])
    assert opts[:fullscreen]
  end

  def test_show_fps
    opts = parse(["--show-fps"])
    assert opts[:show_fps]
  end

  def test_turbo_speed
    opts = parse(["--turbo-speed", "3"])
    assert_equal 3, opts[:turbo_speed]
  end

  def test_turbo_speed_clamps
    opts = parse(["--turbo-speed", "99"])
    assert_equal 4, opts[:turbo_speed]
  end

  def test_locale
    opts = parse(["--locale", "ja"])
    assert_equal "ja", opts[:locale]
  end

  def test_version_flag
    opts = parse(["--version"])
    assert opts[:version]
  end

  def test_help_flag
    opts = parse(["--help"])
    assert opts[:help]
  end

  # -- combinations --

  def test_flags_with_rom
    opts = parse(["-s", "2", "--mute", "pokemon.gba"])
    assert_equal 2, opts[:scale]
    assert opts[:mute]
    assert_equal "pokemon.gba", opts[:rom]
  end

  def test_rom_before_flags
    opts = parse(["game.gba", "--scale", "4"])
    assert_equal "game.gba", opts[:rom]
    assert_equal 4, opts[:scale]
  end

  # -- parser included for help output --

  def test_parser_present
    opts = parse([])
    assert_kind_of OptionParser, opts[:parser]
  end

  def test_help_output_includes_banner
    opts = parse([])
    help = opts[:parser].to_s
    assert_includes help, "Usage: teek-mgba"
    assert_includes help, "GBA emulator"
  end

  # -- apply --

  class MockConfig
    attr_accessor :scale, :volume, :muted, :show_fps, :turbo_speed, :locale

    def initialize
      @scale = 3
      @volume = 100
      @muted = false
      @show_fps = false
      @turbo_speed = 0
      @locale = 'auto'
    end
  end

  def test_apply_overrides_config
    config = MockConfig.new
    Teek::MGBA::CLI.apply(config, { scale: 2, volume: 50, mute: true, show_fps: true })
    assert_equal 2, config.scale
    assert_equal 50, config.volume
    assert config.muted
    assert config.show_fps
  end

  def test_apply_skips_unset_options
    config = MockConfig.new
    Teek::MGBA::CLI.apply(config, {})
    assert_equal 3, config.scale
    assert_equal 100, config.volume
    refute config.muted
  end

  def test_apply_locale
    config = MockConfig.new
    Teek::MGBA::CLI.apply(config, { locale: 'ja' })
    assert_equal 'ja', config.locale
  end

  def test_apply_turbo_speed
    config = MockConfig.new
    Teek::MGBA::CLI.apply(config, { turbo_speed: 3 })
    assert_equal 3, config.turbo_speed
  end

  # -- invalid args --

  def test_unknown_flag_raises
    assert_raises(OptionParser::InvalidOption) { parse(["--bogus"]) }
  end

  def test_missing_scale_value_raises
    assert_raises(OptionParser::MissingArgument) { parse(["--scale"]) }
  end
end
