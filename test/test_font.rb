# frozen_string_literal: true

# Tests for C-level font measurement (ext/teek/tkfont.c).
#
# Use cases:
#   - Text truncation with ellipsis: measure_chars to find how much fits,
#     then slice the string and append "..."
#   - Dynamic column sizing: text_width to compute ideal widths
#   - Custom text layout: font_metrics for line height calculations

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestFont < Minitest::Test
  include TeekTestHelper

  # -- text_width --

  def test_text_width_returns_integer
    assert_tk_app("text_width returns integer", method(:app_text_width_returns_integer))
  end

  def app_text_width_returns_integer
    w = app.text_width('TkDefaultFont', 'Hello')
    raise "expected Integer, got #{w.class}" unless w.is_a?(Integer)
    raise "expected positive width, got #{w}" unless w > 0
  end

  def test_text_width_longer_string_is_wider
    assert_tk_app("longer string has greater width", method(:app_text_width_longer))
  end

  def app_text_width_longer
    short = app.text_width('TkDefaultFont', 'Hi')
    long = app.text_width('TkDefaultFont', 'Hello World, this is a longer string')
    raise "expected long (#{long}) > short (#{short})" unless long > short
  end

  def test_text_width_empty_string
    assert_tk_app("empty string has zero width", method(:app_text_width_empty))
  end

  def app_text_width_empty
    w = app.text_width('TkDefaultFont', '')
    raise "expected 0, got #{w}" unless w == 0
  end

  def test_text_width_with_font_spec
    assert_tk_app("text_width works with font spec", method(:app_text_width_font_spec))
  end

  def app_text_width_font_spec
    w = app.text_width('Helvetica 12', 'Hello')
    raise "expected positive width, got #{w}" unless w > 0
  end

  # -- font_metrics --

  def test_font_metrics_returns_hash
    assert_tk_app("font_metrics returns hash with keys", method(:app_font_metrics_hash))
  end

  def app_font_metrics_hash
    m = app.font_metrics('TkDefaultFont')
    raise "expected Hash, got #{m.class}" unless m.is_a?(Hash)
    [:ascent, :descent, :linespace].each do |k|
      raise "missing key #{k}" unless m.key?(k)
      raise "#{k} should be Integer, got #{m[k].class}" unless m[k].is_a?(Integer)
      raise "#{k} should be positive, got #{m[k]}" unless m[k] > 0
    end
  end

  def test_font_metrics_linespace_is_sum
    assert_tk_app("linespace == ascent + descent", method(:app_font_metrics_linespace))
  end

  def app_font_metrics_linespace
    m = app.font_metrics('TkDefaultFont')
    expected = m[:ascent] + m[:descent]
    raise "linespace #{m[:linespace]} != ascent #{m[:ascent]} + descent #{m[:descent]}" unless m[:linespace] == expected
  end

  def test_font_metrics_with_font_spec
    assert_tk_app("font_metrics works with font spec", method(:app_font_metrics_font_spec))
  end

  def app_font_metrics_font_spec
    m = app.font_metrics('Helvetica 12')
    raise "expected positive ascent, got #{m[:ascent]}" unless m[:ascent] > 0
  end

  # -- measure_chars --

  def test_measure_chars_returns_hash
    assert_tk_app("measure_chars returns hash", method(:app_measure_chars_hash))
  end

  def app_measure_chars_hash
    r = app.measure_chars('TkDefaultFont', 'Hello World', 50)
    raise "expected Hash, got #{r.class}" unless r.is_a?(Hash)
    raise "missing :bytes" unless r.key?(:bytes)
    raise "missing :width" unless r.key?(:width)
    raise ":bytes should be Integer" unless r[:bytes].is_a?(Integer)
    raise ":width should be Integer" unless r[:width].is_a?(Integer)
  end

  def test_measure_chars_respects_limit
    assert_tk_app("measure_chars respects pixel limit", method(:app_measure_chars_limit))
  end

  def app_measure_chars_limit
    text = 'Hello World, this is a long string for measurement'
    full_width = app.text_width('TkDefaultFont', text)
    limit = full_width / 2
    r = app.measure_chars('TkDefaultFont', text, limit)
    raise "bytes #{r[:bytes]} should be less than full length #{text.bytesize}" unless r[:bytes] < text.bytesize
    raise "width #{r[:width]} should be <= limit #{limit}" unless r[:width] <= limit
  end

  def test_measure_chars_unlimited
    assert_tk_app("measure_chars with -1 returns full text", method(:app_measure_chars_unlimited))
  end

  def app_measure_chars_unlimited
    text = 'Hello'
    r = app.measure_chars('TkDefaultFont', text, -1)
    raise "expected all bytes (#{text.bytesize}), got #{r[:bytes]}" unless r[:bytes] == text.bytesize
  end

  def test_measure_chars_whole_words
    assert_tk_app("measure_chars whole_words option", method(:app_measure_chars_whole_words))
  end

  def app_measure_chars_whole_words
    text = 'Hello World Foo'
    # Get width that fits "Hello " but not "Hello World"
    w1 = app.text_width('TkDefaultFont', 'Hello ')
    w2 = app.text_width('TkDefaultFont', 'Hello World')
    limit = (w1 + w2) / 2  # between the two

    r = app.measure_chars('TkDefaultFont', text, limit, whole_words: true)
    fitted = text[0, r[:bytes]]
    raise "expected word break, got '#{fitted}'" if fitted.include?('Wor') && !fitted.include?('World')
  end
end
