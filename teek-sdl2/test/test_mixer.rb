# frozen_string_literal: true

require_relative "test_helper"
require "teek/sdl2"
require "tmpdir"
require "fileutils"

# Use SDL dummy audio driver so tests work without sound hardware (CI, Docker)
ENV['SDL_AUDIODRIVER'] ||= 'dummy'

class TestMixer < Minitest::Test
  include TeekSDL2TestHelper

  def setup
    Teek::SDL2.open_audio
    @sound = Teek::SDL2::Sound.new(sample_wav_path)
  end

  def teardown
    @sound&.destroy unless @sound&.destroyed?
    Teek::SDL2.close_audio
  end

  # -- playing? --------------------------------------------------------------

  def test_playing_after_play
    ch = @sound.play
    refute_equal(-1, ch, "no free mixer channel - leaked from a prior test?")
    assert Teek::SDL2.playing?(ch), "channel should be playing right after play"
  end

  def test_not_playing_after_halt
    ch = @sound.play
    refute_equal(-1, ch, "no free mixer channel - leaked from a prior test?")
    Teek::SDL2.halt(ch)
    sleep 0.05
    refute Teek::SDL2.playing?(ch), "channel should not be playing after halt"
  end

  # -- pause/resume channel --------------------------------------------------

  def test_pause_and_resume_channel
    ch = @sound.play(loops: -1)
    refute_equal(-1, ch, "no free mixer channel - leaked from a prior test?")
    assert Teek::SDL2.playing?(ch)
    refute Teek::SDL2.channel_paused?(ch)

    # Mix_Pause/Mix_Paused are synchronous state flags, not asynchronous
    # mix-thread effects - the state is correct the instant the call
    # returns, so no wait_until here (it would only mask a genuinely
    # wrong/corrupted read, not a timing issue).
    Teek::SDL2.pause_channel(ch)
    assert Teek::SDL2.channel_paused?(ch), "channel should be paused"

    Teek::SDL2.resume_channel(ch)
    refute Teek::SDL2.channel_paused?(ch), "channel should not be paused after resume"
  end

  # -- channel_volume --------------------------------------------------------

  def test_channel_volume_set_and_query
    ch = @sound.play(loops: -1)
    refute_equal(-1, ch, "no free mixer channel - leaked from a prior test?")
    Teek::SDL2.channel_volume(ch, 64)
    vol = Teek::SDL2.channel_volume(ch)
    assert_equal 64, vol
  end

  # -- fade_out_music --------------------------------------------------------

  def test_fade_out_music_no_error
    # Should not raise even with no music playing
    Teek::SDL2.fade_out_music(100)
  end

  # -- fade_out_channel ------------------------------------------------------

  def test_fade_out_channel
    ch = @sound.play(loops: -1)
    refute_equal(-1, ch, "no free mixer channel - leaked from a prior test?")
    Teek::SDL2.fade_out_channel(ch, 100)
    sleep 0.15
    refute Teek::SDL2.playing?(ch), "channel should stop after fade out"
  end

  # -- Sound#play fade_ms ---------------------------------------------------

  def test_sound_play_with_fade_ms
    ch = @sound.play(fade_ms: 100)
    refute_equal(-1, ch, "no free mixer channel - leaked from a prior test?")
    assert Teek::SDL2.playing?(ch)
  end

  # -- Music#play fade_ms ---------------------------------------------------

  def test_music_play_with_fade_ms
    dir = File.expand_path('../../sample/yam/assets', __dir__)
    music_path = File.join(dir, 'music.mp3')
    skip "music.mp3 not found" unless File.exist?(music_path)

    music = Teek::SDL2::Music.new(music_path)
    music.play(fade_ms: 200)
    assert music.playing?
    music.stop
    music.destroy
  end

  # -- master_volume (SDL2_mixer >= 2.6) ------------------------------------

  def test_master_volume
    prev = Teek::SDL2.master_volume
    Teek::SDL2.master_volume = 64
    assert_equal 64, Teek::SDL2.master_volume
    Teek::SDL2.master_volume = prev
  rescue NotImplementedError => e
    assert_match(/SDL2_mixer >= 2\.6/, e.message)
  end

  # -- audio_open? -------------------------------------------------------

  def test_audio_open_p_reflects_open_and_close
    assert Teek::SDL2.audio_open?, "setup already opened it"

    Teek::SDL2.close_audio
    refute Teek::SDL2.audio_open?

    Teek::SDL2.open_audio # so the shared before_teardown/this test's own teardown find it open again
  end

  # -- -1 channel guard on the query wrappers -------------------------------

  def test_playing_p_rejects_negative_one
    error = assert_raises(ArgumentError) { Teek::SDL2.playing?(-1) }
    assert_match(/count-of-all-playing-channels/, error.message)
  end

  def test_channel_paused_p_rejects_negative_one
    error = assert_raises(ArgumentError) { Teek::SDL2.channel_paused?(-1) }
    assert_match(/count-of-all-paused-channels/, error.message)
  end

  def test_halt_negative_one_still_means_halt_all
    a = @sound.play(loops: -1)
    b = @sound.play(loops: -1)
    refute_equal(-1, a, "no free mixer channel - leaked from a prior test?")
    refute_equal(-1, b, "no free mixer channel - leaked from a prior test?")

    Teek::SDL2.halt(-1)

    refute Teek::SDL2.playing?(a)
    refute Teek::SDL2.playing?(b)
  end

  private

  def sample_wav_path
    File.expand_path('../../sample/yam/assets/click.wav', __dir__)
  end
end
