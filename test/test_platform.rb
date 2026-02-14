# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/teek/platform'

class TestPlatform < Minitest::Test
  def test_exactly_one_platform_detected
    p = Teek.platform
    detected = [p.darwin?, p.linux?, p.windows?].count(true)
    assert_equal 1, detected, "Expected exactly one platform, got: #{p}"
  end

  def test_to_s_matches_predicate
    p = Teek.platform
    if p.darwin?
      assert_equal 'darwin', p.to_s
    elsif p.windows?
      assert_equal 'windows', p.to_s
    elsif p.linux?
      assert_equal 'linux', p.to_s
    end
  end

  def test_darwin_detection
    p = Teek::Platform.new('arm64-darwin24')
    assert p.darwin?
    refute p.linux?
    refute p.windows?
  end

  def test_linux_detection
    p = Teek::Platform.new('x86_64-linux')
    refute p.darwin?
    assert p.linux?
    refute p.windows?
  end

  def test_windows_mingw_detection
    p = Teek::Platform.new('x64-mingw-ucrt')
    refute p.darwin?
    refute p.linux?
    assert p.windows?
  end

  def test_windows_mswin_detection
    p = Teek::Platform.new('x64-mswin64_140')
    refute p.darwin?
    refute p.linux?
    assert p.windows?
  end

  def test_singleton
    assert_same Teek.platform, Teek.platform
  end
end
