# frozen_string_literal: true

require "minitest/autorun"
require "teek/mgba/headless"
require "tmpdir"

class TestRecorder < Minitest::Test
  TEST_ROM = File.expand_path("fixtures/test.gba", __dir__)

  def setup
    skip "Run: ruby teek-mgba/scripts/generate_test_rom.rb" unless File.exist?(TEST_ROM)
  end

  def test_record_and_decode_round_trip
    skip "ffmpeg not installed" unless ffmpeg_available?

    Dir.mktmpdir do |dir|
      trec_path = File.join(dir, "test.trec")
      output_path = File.join(dir, "test.mp4")
      frames = 10

      # Record
      Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
        player.start_recording(trec_path)
        player.step(frames)
        player.stop_recording
      end

      assert File.exist?(trec_path)
      assert_operator File.size(trec_path), :>, 32 # at least header

      # Decode → encode
      info = Teek::MGBA::RecorderDecoder.decode(trec_path, output_path)

      assert_equal 240, info[:width]
      assert_equal 160, info[:height]
      assert_equal frames, info[:frame_count]
      assert_in_delta 59.7272, info[:fps], 0.01
      assert_equal 44100, info[:audio_rate]
      assert_equal 2, info[:audio_channels]

      # Output video file should exist and have data
      assert File.exist?(output_path)
      assert_operator File.size(output_path), :>, 0
    end
  end

  def test_decode_without_ffmpeg_raises
    Dir.mktmpdir do |dir|
      trec_path = File.join(dir, "test.trec")

      Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
        player.start_recording(trec_path)
        player.step(1)
        player.stop_recording
      end

      output_path = File.join(dir, "test.mp4")
      with_empty_path do
        assert_raises(Teek::MGBA::RecorderDecoder::FfmpegNotFound) do
          Teek::MGBA::RecorderDecoder.decode(trec_path, output_path)
        end
      end
    end
  end

  def test_delta_compression_reduces_size
    Dir.mktmpdir do |dir|
      trec_path = File.join(dir, "test.trec")

      Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
        player.start_recording(trec_path)
        player.step(30)
        player.stop_recording
      end

      trec_size = File.size(trec_path)
      raw_size = 240 * 160 * 4 * 30 # ~4.6MB uncompressed video alone
      assert_operator trec_size, :<, raw_size, "Compressed .trec should be smaller than raw"
    end
  end

  def test_recording_state
    Dir.mktmpdir do |dir|
      trec_path = File.join(dir, "test.trec")

      Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
        refute player.recording?
        player.start_recording(trec_path)
        assert player.recording?
        player.step(5)
        player.stop_recording
        refute player.recording?
      end
    end
  end

  def test_close_stops_recording
    Dir.mktmpdir do |dir|
      trec_path = File.join(dir, "test.trec")

      player = Teek::MGBA::HeadlessPlayer.new(TEST_ROM)
      player.start_recording(trec_path)
      player.step(5)
      player.close # should stop recording gracefully

      assert File.exist?(trec_path)
      assert_operator File.size(trec_path), :>, 32
    end
  end

  def test_double_start_raises
    Dir.mktmpdir do |dir|
      Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
        player.start_recording(File.join(dir, "a.trec"))
        assert_raises(RuntimeError) do
          player.start_recording(File.join(dir, "b.trec"))
        end
        player.stop_recording
      end
    end
  end

  def test_header_format
    Dir.mktmpdir do |dir|
      trec_path = File.join(dir, "test.trec")

      Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
        player.start_recording(trec_path)
        player.step(1)
        player.stop_recording
      end

      File.open(trec_path, 'rb') do |f|
        header = f.read(32)
        assert_equal "TEEKREC\0", header[0, 8]
        assert_equal 1, header[8].unpack1('C') # version
        w, h = header[9, 4].unpack('v2')
        assert_equal 240, w
        assert_equal 160, h
      end
    end
  end

  def test_footer_present
    Dir.mktmpdir do |dir|
      trec_path = File.join(dir, "test.trec")

      Teek::MGBA::HeadlessPlayer.open(TEST_ROM) do |player|
        player.start_recording(trec_path)
        player.step(5)
        player.stop_recording
      end

      File.open(trec_path, 'rb') do |f|
        f.seek(-8, IO::SEEK_END)
        footer = f.read(8)
        frame_count, magic = footer.unpack('Va4')
        assert_equal 5, frame_count
        assert_equal "TEND", magic
      end
    end
  end

  private

  def ffmpeg_available?
    system('ffmpeg', '-version', out: File::NULL, err: File::NULL)
  rescue Errno::ENOENT
    false
  end

  def with_empty_path
    old_path = ENV['PATH']
    ENV['PATH'] = ''
    yield
  ensure
    ENV['PATH'] = old_path
  end
end
