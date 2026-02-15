# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "json"
require_relative "../../teek-mgba/lib/teek/mgba/config"
require_relative "../../teek-mgba/lib/teek/mgba/locale"
require_relative "../../teek-mgba/lib/teek/mgba/save_state_manager"

class TestSaveStateManager < Minitest::Test
  # Recording mock for the mGBA Core.
  # Responds to the duck-type interface SaveStateManager needs and
  # records every call for test assertions.
  class MockCore
    attr_reader :calls
    attr_accessor :game_code, :checksum, :destroyed, :save_result, :load_result

    def initialize(game_code: "AGB-BTKE", checksum: 0xDEADBEEF)
      @calls = []
      @game_code = game_code
      @checksum = checksum
      @destroyed = false
      @save_result = true
      @load_result = true
    end

    def destroyed?
      @destroyed
    end

    def save_state_to_file(path)
      @calls << [:save_state_to_file, path]
      File.write(path, "STATE") if @save_result
      @save_result
    end

    def load_state_from_file(path)
      @calls << [:load_state_from_file, path]
      @load_result
    end

    def video_buffer_argb
      @calls << [:video_buffer_argb]
      "\x00".b * (240 * 160 * 4)
    end
  end

  # Recording mock for Tk's Tcl interpreter (provides photo_put_block).
  class MockInterp
    attr_reader :calls

    def initialize
      @calls = []
    end

    def photo_put_block(name, pixels, w, h, format:)
      @calls << [:photo_put_block, name, w, h, format]
    end
  end

  # Recording mock for the Teek::App.
  # Records command() calls and exposes a mock interp.
  class MockApp
    attr_reader :calls, :interp

    def initialize
      @calls = []
      @interp = MockInterp.new
    end

    def command(*args, **kwargs)
      @calls << [args, kwargs]
      nil
    end
  end

  def setup
    @dir = Dir.mktmpdir("teek-mgba-ssm-test")
    @config_path = File.join(@dir, "settings.json")
    @config = Teek::MGBA::Config.new(path: @config_path)
    @config.save_state_debounce = 0  # disable debounce for tests
    @states_dir = File.join(@dir, "states")
    @config.states_dir = @states_dir

    @core = MockCore.new
    @app = MockApp.new
    @mgr = new_manager
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def new_manager(core: @core, config: @config, app: @app)
    mgr = Teek::MGBA::SaveStateManager.new(core: core, config: config, app: app)
    mgr.state_dir = mgr.state_dir_for_rom(core)
    mgr
  end

  # -- state_dir_for_rom -----------------------------------------------------

  def test_state_dir_for_rom_includes_game_code_and_crc
    dir = @mgr.state_dir_for_rom(@core)
    assert_includes dir, "AGB-BTKE"
    assert_includes dir, "DEADBEEF"
  end

  def test_state_dir_for_rom_sanitizes_special_chars
    @core.game_code = "AB/CD\\EF"
    dir = @mgr.state_dir_for_rom(@core)
    basename = File.basename(dir)
    refute_match %r{[/\\]}, basename
    assert_includes basename, "AB_CD_EF"
  end

  # -- state_path / screenshot_path ------------------------------------------

  def test_state_path
    assert @mgr.state_path(1).end_with?("state1.ss")
  end

  def test_screenshot_path
    assert @mgr.screenshot_path(1).end_with?("state1.png")
  end

  # -- save_state ------------------------------------------------------------

  def test_save_state_success
    success, msg = @mgr.save_state(1)
    assert success
    assert_includes msg, "1"  # slot number in message
    assert File.exist?(@mgr.state_path(1)), "state file should be written"
  end

  def test_save_state_calls_core
    @mgr.save_state(1)
    save_calls = @core.calls.select { |c| c[0] == :save_state_to_file }
    assert_equal 1, save_calls.size
    assert save_calls[0][1].end_with?("state1.ss")
  end

  def test_save_state_takes_screenshot
    @mgr.save_state(1)
    # Should have called video_buffer_argb
    assert @core.calls.any? { |c| c[0] == :video_buffer_argb }
    # Should have created a Tk photo via app.command
    image_creates = @app.calls.select { |args, _| args[0] == :image && args[1] == :create }
    assert_equal 1, image_creates.size
    # Should have written the photo via app.command
    write_calls = @app.calls.select { |args, _| args[1] == :write }
    assert_equal 1, write_calls.size
    # Should have cleaned up the photo
    delete_calls = @app.calls.select { |args, _| args[0] == :image && args[1] == :delete }
    assert_equal 1, delete_calls.size
  end

  def test_save_state_interp_photo_put_block
    @mgr.save_state(1)
    ppb = @app.interp.calls.select { |c| c[0] == :photo_put_block }
    assert_equal 1, ppb.size
    assert_equal 240, ppb[0][2]  # width
    assert_equal 160, ppb[0][3]  # height
    assert_equal :argb, ppb[0][4]
  end

  def test_save_state_failure
    @core.save_result = false
    success, msg = @mgr.save_state(1)
    refute success
    refute_nil msg
  end

  def test_save_state_with_destroyed_core
    @core.destroyed = true
    success, msg = @mgr.save_state(1)
    refute success
    assert_nil msg
  end

  # -- debounce --------------------------------------------------------------

  def test_save_state_debounce_blocks_rapid_saves
    @config.save_state_debounce = 10.0  # very long debounce
    mgr = new_manager

    success1, _ = mgr.save_state(1)
    assert success1

    success2, msg2 = mgr.save_state(2)
    refute success2
    refute_nil msg2  # should have a "blocked" message
  end

  # -- backup rotation -------------------------------------------------------

  def test_save_state_backup_creates_bak_files
    @mgr.backup = true

    # First save
    @mgr.save_state(1)
    ss = @mgr.state_path(1)
    assert File.exist?(ss)

    # Second save — original should be renamed to .bak
    @mgr.save_state(1)
    assert File.exist?("#{ss}.bak"), ".bak file should exist after second save"
  end

  def test_save_state_no_backup_when_disabled
    @mgr.backup = false

    @mgr.save_state(1)
    ss = @mgr.state_path(1)

    @mgr.save_state(1)
    refute File.exist?("#{ss}.bak"), ".bak should not exist when backup disabled"
  end

  # -- load_state ------------------------------------------------------------

  def test_load_state_success
    # Create a state file first
    @mgr.save_state(1)

    success, msg = @mgr.load_state(1)
    assert success
    assert_includes msg, "1"
    load_calls = @core.calls.select { |c| c[0] == :load_state_from_file }
    assert_equal 1, load_calls.size
  end

  def test_load_state_missing_file
    success, msg = @mgr.load_state(7)
    refute success
    refute_nil msg  # "no state" message
  end

  def test_load_state_failure
    @mgr.save_state(1)  # create the file
    @core.load_result = false

    success, msg = @mgr.load_state(1)
    refute success
    refute_nil msg
  end

  def test_load_state_with_destroyed_core
    @core.destroyed = true
    success, msg = @mgr.load_state(1)
    refute success
    assert_nil msg
  end

  # -- quick save / quick load -----------------------------------------------

  def test_quick_save_uses_configured_slot
    @mgr.quick_save_slot = 3
    @mgr.quick_save
    save_calls = @core.calls.select { |c| c[0] == :save_state_to_file }
    assert_equal 1, save_calls.size
    assert save_calls[0][1].end_with?("state3.ss")
  end

  def test_quick_load_uses_configured_slot
    @mgr.quick_save_slot = 3
    @mgr.quick_save  # create the file first
    @mgr.quick_load
    load_calls = @core.calls.select { |c| c[0] == :load_state_from_file }
    assert_equal 1, load_calls.size
    assert load_calls[0][1].end_with?("state3.ss")
  end

  # -- screenshot failure doesn't break save ---------------------------------

  def test_screenshot_failure_does_not_prevent_save
    # Make interp.photo_put_block raise
    def @app.interp
      obj = Object.new
      def obj.photo_put_block(*)
        raise "boom"
      end
      obj
    end

    success, msg = @mgr.save_state(1)
    assert success, "save should still succeed even if screenshot fails"
    assert File.exist?(@mgr.state_path(1))
  end
end
