# frozen_string_literal: true

require_relative "test_helper"
require "teek/sdl2"
require "tmpdir"
require "fileutils"

# Use SDL dummy audio driver so tests work without sound hardware (CI, Docker)
ENV['SDL_AUDIODRIVER'] ||= 'dummy'

class TestAudioCapture < Minitest::Test
  def setup
    Teek::SDL2.open_audio
    @tmpdir = Dir.mktmpdir("teek_audio_test")
  end

  def teardown
    Teek::SDL2.stop_audio_capture
    Teek::SDL2.close_audio
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_start_and_stop_creates_valid_wav
    path = capture_path("basic")
    Teek::SDL2.start_audio_capture(path)

    sound = Teek::SDL2::Sound.new(sample_wav_path)
    sound.play
    sleep 0.3
    sound.destroy

    Teek::SDL2.stop_audio_capture

    data = File.binread(path)

    # RIFF/WAVE container
    assert_equal "RIFF", data[0..3]
    assert_equal "WAVE", data[8..11]
    assert_equal "fmt ", data[12..15]
    assert_equal "data", data[36..39]

    # Should have audio data beyond the 44-byte header
    assert data.bytesize > 44, "WAV should contain audio data"
  end

  def test_stop_without_start_is_noop
    Teek::SDL2.stop_audio_capture # should not raise
  end

  def test_double_start_raises
    Teek::SDL2.start_audio_capture(capture_path("first"))

    assert_raises(RuntimeError) do
      Teek::SDL2.start_audio_capture(capture_path("second"))
    end

    Teek::SDL2.stop_audio_capture
  end

  def test_wav_header_matches_mixer_format
    path = capture_path("format")
    Teek::SDL2.start_audio_capture(path)
    sleep 0.1
    Teek::SDL2.stop_audio_capture

    data = File.binread(path)

    channels        = data[22..23].unpack1('v')  # uint16 LE
    sample_rate     = data[24..27].unpack1('V')  # uint32 LE
    bits_per_sample = data[34..35].unpack1('v')

    assert_equal 2, channels, "expected stereo"
    assert_equal 44100, sample_rate, "expected 44100 Hz"
    assert_equal 16, bits_per_sample, "expected 16-bit"
  end

  def test_data_size_in_header_matches_file
    path = capture_path("sizes")
    Teek::SDL2.start_audio_capture(path)

    sound = Teek::SDL2::Sound.new(sample_wav_path)
    sound.play
    sleep 0.2
    sound.destroy

    Teek::SDL2.stop_audio_capture

    data = File.binread(path)

    # RIFF size field = total file size - 8
    riff_size = data[4..7].unpack1('V')
    assert_equal data.bytesize - 8, riff_size

    # data chunk size = total file size - 44 (header)
    data_chunk_size = data[40..43].unpack1('V')
    assert_equal data.bytesize - 44, data_chunk_size
  end

  private

  def capture_path(name)
    File.join(@tmpdir, "#{name}.wav")
  end

  def sample_wav_path
    File.expand_path('../../sample/yam/assets/click.wav', __dir__)
  end
end
