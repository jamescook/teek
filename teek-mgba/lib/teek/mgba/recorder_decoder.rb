# frozen_string_literal: true

require 'zlib'
require 'open3'
require 'tempfile'

module Teek
  module MGBA
    # Decodes a .trec file and encodes it to a playable video via ffmpeg.
    #
    # Two-pass approach to avoid writing massive intermediate files:
    #   Pass 1: Extract audio to a small tempfile (~10MB/min), count frames,
    #           collect per-frame change percentages.
    #   Pass 2: Decode video frames one at a time and pipe to ffmpeg's stdin.
    #
    # Only one decoded video frame is in memory at a time, so RAM usage stays
    # constant regardless of recording length.
    #
    # @example
    #   info = RecorderDecoder.decode("recording.trec", "output.mp4")
    #   puts "Encoded #{info[:frame_count]} frames to #{info[:output_path]}"
    #
    # @example Quick stats without encoding
    #   stats = RecorderDecoder.stats("recording.trec")
    #   puts "#{stats[:frame_count]} frames, avg #{stats[:avg_change_pct].round(1)}% change"
    class RecorderDecoder
      class FormatError < StandardError; end
      class FfmpegNotFound < StandardError; end

      DEFAULT_VIDEO_CODEC = 'libx264'
      DEFAULT_AUDIO_CODEC = 'aac'

      # Quick scan of a .trec file — no ffmpeg needed.
      # Reads header + per-frame change bytes, skips video/audio data.
      # @param trec_path [String]
      # @return [Hash] :frame_count, :width, :height, :fps, :duration,
      #   :avg_change_pct, :raw_video_size, :audio_rate, :audio_channels
      def self.stats(trec_path)
        new(trec_path, nil).stats
      end

      # Decode a .trec file and encode to a playable video file.
      # @param trec_path [String] path to .trec file
      # @param output_path [String] output video path (e.g. "out.mp4", "out.mkv")
      # @param video_codec [String] ffmpeg video codec (default: libx264)
      # @param audio_codec [String] ffmpeg audio codec (default: aac)
      # @param scale [Integer, nil] output scale factor (nil = native)
      # @param ffmpeg_args [Array<String>, nil] raw ffmpeg output args (overrides codecs)
      # @param progress [Boolean] show encoding progress (default: true)
      # @return [Hash] :output_path, :frame_count, :width, :height, :fps,
      #   :avg_change_pct, :raw_video_size, :audio_rate, :audio_channels
      def self.decode(trec_path, output_path, video_codec: DEFAULT_VIDEO_CODEC,
                      audio_codec: DEFAULT_AUDIO_CODEC, scale: nil,
                      ffmpeg_args: nil, progress: true)
        new(trec_path, output_path,
            video_codec: video_codec, audio_codec: audio_codec,
            scale: scale, ffmpeg_args: ffmpeg_args, progress: progress).decode
      end

      def initialize(trec_path, output_path, video_codec: DEFAULT_VIDEO_CODEC,
                     audio_codec: DEFAULT_AUDIO_CODEC, scale: nil,
                     ffmpeg_args: nil, progress: true)
        @trec_path = trec_path
        @output_path = output_path
        @video_codec = video_codec
        @audio_codec = audio_codec
        @scale = scale
        @ffmpeg_args = ffmpeg_args
        @progress = progress
      end

      # Quick stats scan — reads only header + 1 byte per frame.
      def stats
        header = nil
        frame_count = 0
        total_change = 0

        File.open(@trec_path, 'rb') do |f|
          header = read_header(f)

          until f.eof?
            break if at_footer?(f)

            change_pct = f.read(1)&.unpack1('C') or break
            total_change += change_pct

            video_len = read_u32(f) or break
            f.seek(video_len, IO::SEEK_CUR)

            audio_len = read_u32(f) or break
            f.seek(audio_len, IO::SEEK_CUR)

            frame_count += 1
          end
        end

        fps = header[:fps_num].to_f / header[:fps_den]
        frame_size = header[:width] * header[:height] * 4

        {
          frame_count: frame_count,
          width: header[:width],
          height: header[:height],
          fps: fps,
          duration: frame_count / fps,
          avg_change_pct: frame_count > 0 ? total_change.to_f / frame_count : 0,
          raw_video_size: frame_count * frame_size,
          audio_rate: header[:audio_rate],
          audio_channels: header[:audio_channels],
        }
      end

      def decode
        check_ffmpeg!

        header = nil
        frame_count = 0
        total_change = 0

        # Pass 1: parse header, extract audio to tempfile, count frames.
        # Video chunks are skipped (seek, not read) to keep this fast.
        audio_tmp = Tempfile.new(['trec_audio', '.raw'])
        audio_tmp.binmode

        File.open(@trec_path, 'rb') do |f|
          header = read_header(f)

          until f.eof?
            break if at_footer?(f)

            change_pct = f.read(1)&.unpack1('C') or break
            total_change += change_pct

            video_len = read_u32(f) or break
            f.seek(video_len, IO::SEEK_CUR)

            audio_len = read_u32(f) or break
            audio_tmp.write(f.read(audio_len)) if audio_len > 0

            frame_count += 1
          end
        end

        audio_tmp.flush
        fps = header[:fps_num].to_f / header[:fps_den]
        frame_size = header[:width] * header[:height] * 4

        # Pass 2: decode video frames and pipe to ffmpeg.
        encode(header, fps, audio_tmp.path, frame_count)

        {
          output_path: @output_path,
          frame_count: frame_count,
          width: header[:width],
          height: header[:height],
          fps: fps,
          avg_change_pct: frame_count > 0 ? total_change.to_f / frame_count : 0,
          raw_video_size: frame_count * frame_size,
          audio_rate: header[:audio_rate],
          audio_channels: header[:audio_channels],
        }
      ensure
        audio_tmp&.close!
      end

      private

      def check_ffmpeg!
        Open3.capture2e('ffmpeg', '-version')
      rescue Errno::ENOENT
        raise FfmpegNotFound, "ffmpeg not found in PATH"
      end

      # Pipe decoded video frames to ffmpeg stdin while ffmpeg reads audio
      # from the tempfile. One frame in memory at a time.
      def encode(header, fps, audio_path, total_frames)
        frame_size = header[:width] * header[:height] * 4
        prev_frame = ("\0" * frame_size).b
        cmd = build_ffmpeg_cmd(header, fps, audio_path)

        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
          err_reader = Thread.new { stderr.read }
          progress_reader = @progress ? start_progress_reader(stdout, total_frames) : nil

          File.open(@trec_path, 'rb') do |f|
            f.seek(32) # skip header

            until f.eof?
              break if at_footer?(f)

              f.seek(1, IO::SEEK_CUR) # skip change_pct byte

              # Decode one video frame
              video_len = read_u32(f) or break
              compressed = f.read(video_len)
              delta = Zlib::Inflate.inflate(compressed)
              frame = Teek::MGBA.xor_delta(delta, prev_frame)
              prev_frame = frame
              stdin.write(frame)

              # Skip audio (already extracted in pass 1)
              audio_len = read_u32(f) or break
              f.seek(audio_len, IO::SEEK_CUR) if audio_len > 0
            end
          end

          stdin.close
          progress_reader&.join
          $stderr.print "\r\e[K" if @progress
          status = wait_thr.value
          unless status.success?
            raise "ffmpeg failed (exit #{status.exitstatus}): #{err_reader.value}"
          end
        end
      end

      # Read ffmpeg's -progress output on stdout and print a progress line.
      def start_progress_reader(stdout, total_frames)
        Thread.new do
          current_frame = 0
          encode_fps = 0.0
          last_print = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          stdout.each_line do |line|
            case line
            when /\Aframe=(\d+)/
              current_frame = $1.to_i
            when /\Afps=([\d.]+)/
              encode_fps = $1.to_f
            when /\Aprogress=/
              now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              is_done = line.start_with?('progress=end')
              if is_done || now - last_print >= 0.5
                pct = total_frames > 0 ? (current_frame * 100.0 / total_frames) : 0
                fps_str = encode_fps > 0 ? " @ #{'%.1f' % encode_fps} fps" : ""
                $stderr.print "\rEncoding: #{current_frame}/#{total_frames} " \
                              "(#{'%.1f' % pct}%)#{fps_str}\e[K"
                last_print = now
              end
            end
          end
        end
      end

      # Build the ffmpeg argument list.
      #
      # Video input (pipe:0): raw frames in BGRA pixel order.
      # mGBA's video_buffer_argb stores each pixel as a uint32 0xAARRGGBB;
      # on little-endian systems the byte layout is B-G-R-A, so ffmpeg
      # must be told -pix_fmt bgra (not argb).
      #
      # Audio input: raw PCM, signed 16-bit little-endian, stereo interleaved
      # (LRLRLR...) at the GBA's native sample rate (44100 Hz).
      #
      # -pix_fmt yuv420p on output ensures broad player/browser compatibility.
      def build_ffmpeg_cmd(header, fps, audio_path)
        cmd = %W[
          ffmpeg -y -loglevel error
          -f rawvideo -pix_fmt bgra
          -s #{header[:width]}x#{header[:height]}
          -r #{format('%.4f', fps)}
          -i pipe:0
          -f s16le -ar #{header[:audio_rate]}
          -ac #{header[:audio_channels]}
          -i #{audio_path}
        ]
        if @scale && @scale > 1
          w = header[:width] * @scale
          h = header[:height] * @scale
          # Use -sws_flags instead of scale=W:H:flags=neighbor — the inline
          # flags= syntax produced vertically-oriented output on ffmpeg 7.1.1.
          cmd.push('-vf', "scale=#{w}:#{h}",
                   '-sws_flags', 'neighbor')
        end
        if @ffmpeg_args
          cmd.concat(@ffmpeg_args)
        else
          cmd.push('-c:v', @video_codec, '-pix_fmt', 'yuv420p',
                   '-c:a', @audio_codec)
        end
        cmd.push('-progress', 'pipe:1') if @progress
        cmd.push(@output_path)
        cmd
      end

      def read_header(f)
        raw = f.read(32)
        raise FormatError, "File too small for header" unless raw && raw.bytesize == 32

        magic = raw[0, 8]
        raise FormatError, "Invalid magic: #{magic.inspect}" unless magic == Recorder::MAGIC

        version = raw[8].unpack1('C')
        raise FormatError, "Unsupported version: #{version}" unless version == Recorder::VERSION

        width, height = raw[9, 4].unpack('v2')
        fps_num, fps_den = raw[13, 8].unpack('V2')
        audio_rate = raw[21, 4].unpack1('V')
        audio_channels, audio_bits = raw[25, 2].unpack('C2')

        { width: width, height: height,
          fps_num: fps_num, fps_den: fps_den,
          audio_rate: audio_rate,
          audio_channels: audio_channels,
          audio_bits: audio_bits }
      end

      # Check if we're at the 8-byte footer. If not, rewind to where we were.
      def at_footer?(f)
        pos = f.pos
        marker = f.read(8)
        if marker && marker.bytesize == 8
          _, magic = marker.unpack('Va4')
          return true if magic == Recorder::FOOTER_MAGIC
        end
        f.seek(pos)
        false
      end

      def read_u32(f)
        raw = f.read(4)
        return nil unless raw && raw.bytesize == 4
        raw.unpack1('V')
      end
    end
  end
end
