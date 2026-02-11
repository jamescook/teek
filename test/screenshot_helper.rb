# frozen_string_literal: true

# Screenshot comparison helpers for SDL2 visual regression testing.
#
# Uses Renderer#read_pixels to capture GPU framebuffer output and
# ImageMagick to convert raw RGBA to PNG and compare against blessed baselines.
#
# Directory layout:
#   screenshots/blessed/{platform}/    — committed gold images
#   screenshots/unverified/{platform}/ — generated during test (gitignored)
#   screenshots/diffs/{platform}/      — diff images on failure (gitignored)

require 'fileutils'
require 'open3'

module ScreenshotHelper
  SCREENSHOTS_ROOT = File.expand_path('../screenshots', __dir__)

  PLATFORM = case RUBY_PLATFORM
             when /darwin/  then 'darwin'
             when /linux/   then 'linux'
             when /mingw|mswin/ then 'windows'
             else 'unknown'
             end

  # Default pixel difference threshold for ImageMagick compare (AE metric).
  # GPU drivers may produce minor anti-aliasing variations across runs.
  THRESHOLD = Integer(ENV.fetch('SCREENSHOT_THRESHOLD', 100))

  def self.blessed_dir
    File.join(SCREENSHOTS_ROOT, 'blessed', PLATFORM)
  end

  def self.unverified_dir
    File.join(SCREENSHOTS_ROOT, 'unverified', PLATFORM)
  end

  def self.diffs_dir
    File.join(SCREENSHOTS_ROOT, 'diffs', PLATFORM)
  end

  def self.setup_dirs
    FileUtils.mkdir_p(blessed_dir)
    FileUtils.mkdir_p(unverified_dir)
    FileUtils.mkdir_p(diffs_dir)
  end

  # Check if ImageMagick is available.
  def self.imagemagick?
    return @imagemagick if defined?(@imagemagick)
    _, _, status = Open3.capture3('magick', '-version')
    @imagemagick = status.success?
  rescue Errno::ENOENT
    @imagemagick = false
  end

  # Save raw RGBA pixels as PNG via ImageMagick.
  def self.save_png(pixels, width, height, path)
    cmd = ['magick', '-size', "#{width}x#{height}", '-depth', '8', 'rgba:-', path]
    IO.popen(cmd, 'wb') { |io| io.write(pixels) }
    raise "magick convert failed for #{path}" unless $?.success?
  end

  # Compare two PNGs with ImageMagick compare (AE metric).
  # Returns [passed, pixel_diff, output].
  def self.compare(expected, actual, diff_output)
    cmd = ['magick', 'compare', '-metric', 'AE', expected, actual, diff_output]
    stdout, stderr, status = Open3.capture3(*cmd)
    output = stdout + stderr

    pixel_diff = output[/(\d+)/]&.to_i
    passed = pixel_diff ? pixel_diff <= THRESHOLD : status.success?

    [passed, pixel_diff, output.strip]
  end

  # Assert that the current renderer output matches the blessed screenshot.
  #
  # Captures pixels from the renderer, saves to unverified/{platform}/{name}.png,
  # then compares against blessed/{platform}/{name}.png.
  #
  #   assert_sdl2_screenshot(renderer, "red_rect")
  #
  def assert_sdl2_screenshot(renderer, name, message: nil)
    ScreenshotHelper.setup_dirs

    unless ScreenshotHelper.imagemagick?
      skip "ImageMagick not installed — skipping screenshot comparison"
    end

    w, h = renderer.output_size
    pixels = renderer.read_pixels

    unverified = File.join(ScreenshotHelper.unverified_dir, "#{name}.png")
    ScreenshotHelper.save_png(pixels, w, h, unverified)

    blessed = File.join(ScreenshotHelper.blessed_dir, "#{name}.png")

    unless File.exist?(blessed)
      flunk "No blessed screenshot for '#{name}'. " \
            "Inspect #{unverified} and run: rake screenshots:bless"
    end

    diff = File.join(ScreenshotHelper.diffs_dir, "#{name}_diff.png")
    passed, pixel_diff, output = ScreenshotHelper.compare(blessed, unverified, diff)

    if passed
      FileUtils.rm_f(diff)
    else
      msg = message || "Screenshot '#{name}' differs by #{pixel_diff} pixels (threshold: #{ScreenshotHelper::THRESHOLD})"
      msg += "\n  Blessed:    #{blessed}"
      msg += "\n  Unverified: #{unverified}"
      msg += "\n  Diff:       #{diff}"
      flunk msg
    end
  end
end
