# frozen_string_literal: true

require "minitest/autorun"
require "teek/mgba/headless"
require "tmpdir"

class TestHeadlessPlayer < Minitest::Test
  TEST_ROM = File.expand_path("fixtures/test.gba", __dir__)

  def setup
    skip "Run: ruby teek-mgba/scripts/generate_test_rom.rb" unless File.exist?(TEST_ROM)
  end

  # -- Lifecycle ---------------------------------------------------------------

  def test_open_and_close
    player = Teek::MGBA::HeadlessPlayer.new(TEST_ROM)
    refute player.closed?
    player.close
    assert player.closed?
  end

  def test_double_close_is_safe
    player = Teek::MGBA::HeadlessPlayer.new(TEST_ROM)
    player.close
    player.close # should not raise
    assert player.closed?
  end

  def test_block_form
    result = Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      refute player.closed?
      :ok
    end
    assert_equal :ok, result
  end

  def test_block_form_closes_on_exception
    assert_raises(RuntimeError) do
      Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
        @ref = player
        raise "boom"
      end
    end
    assert @ref.closed?
  end

  # -- Stepping ----------------------------------------------------------------

  def test_step_single_frame
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      player.step # should not raise
    end
  end

  def test_step_multiple_frames
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      player.step(60) # should not raise
    end
  end

  def test_step_after_close_raises
    player = Teek::MGBA::HeadlessPlayer.new(TEST_ROM)
    player.close
    assert_raises(RuntimeError) { player.step }
  end

  # -- Input -------------------------------------------------------------------

  def test_press_and_release
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      player.press(Teek::MGBA::KEY_A | Teek::MGBA::KEY_START)
      player.step
      player.release_all
      player.step
    end
  end

  # -- Buffers -----------------------------------------------------------------

  def test_video_buffer_argb_size
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      player.step
      buf = player.video_buffer_argb
      assert_equal 240 * 160 * 4, buf.bytesize
    end
  end

  def test_audio_buffer_returns_data
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      player.step
      buf = player.audio_buffer
      assert_kind_of String, buf
    end
  end

  # -- Dimensions --------------------------------------------------------------

  def test_width_and_height
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      assert_equal 240, player.width
      assert_equal 160, player.height
    end
  end

  # -- ROM metadata ------------------------------------------------------------

  def test_title
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      assert_equal "TEEKTEST", player.title
    end
  end

  def test_game_code
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      assert_equal "AGB-BTKE", player.game_code
    end
  end

  def test_maker_code
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      assert_equal "01", player.maker_code
    end
  end

  def test_checksum
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      assert_kind_of Integer, player.checksum
    end
  end

  def test_platform
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      assert_equal "GBA", player.platform
    end
  end

  def test_rom_size
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      assert_operator player.rom_size, :>, 0
    end
  end

  # -- Save states -------------------------------------------------------------

  def test_save_and_load_state
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.ss1")

      Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
        player.step(10)
        assert player.save_state(path)
        assert File.exist?(path)

        player.step(60)
        assert player.load_state(path)
      end
    end
  end

  # -- Rewind ------------------------------------------------------------------

  def test_rewind_init_and_count
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      player.rewind_init(3)
      assert_equal 0, player.rewind_count

      player.step
      player.rewind_push
      assert_equal 1, player.rewind_count

      player.step
      player.rewind_push
      assert_equal 2, player.rewind_count
    end
  end

  def test_rewind_pop
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      player.rewind_init(5)
      player.step(10)
      player.rewind_push
      player.step(10)
      assert player.rewind_pop
      assert_equal 0, player.rewind_count
    end
  end

  def test_rewind_pop_empty_returns_false
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      player.rewind_init(3)
      refute player.rewind_pop
    end
  end

  def test_rewind_deinit
    Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
      player.rewind_init(3)
      player.step
      player.rewind_push
      player.rewind_deinit
      assert_equal 0, player.rewind_count
    end
  end
end
