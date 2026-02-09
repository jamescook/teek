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
    assert_tk_app("text_width returns integer") do
      w = app.text_width('TkDefaultFont', 'Hello')
      assert_kind_of Integer, w
      assert_operator w, :>, 0, "expected positive width"
    end
  end

  def test_text_width_longer_string_is_wider
    assert_tk_app("longer string has greater width") do
      short = app.text_width('TkDefaultFont', 'Hi')
      long = app.text_width('TkDefaultFont', 'Hello World, this is a longer string')
      assert_operator long, :>, short
    end
  end

  def test_text_width_empty_string
    assert_tk_app("empty string has zero width") do
      w = app.text_width('TkDefaultFont', '')
      assert_equal 0, w
    end
  end

  def test_text_width_with_font_spec
    assert_tk_app("text_width works with font spec") do
      w = app.text_width('Helvetica 12', 'Hello')
      assert_operator w, :>, 0, "expected positive width"
    end
  end

  # -- font_metrics --

  def test_font_metrics_returns_hash
    assert_tk_app("font_metrics returns hash with keys") do
      m = app.font_metrics('TkDefaultFont')
      assert_kind_of Hash, m
      [:ascent, :descent, :linespace].each do |k|
        assert m.key?(k), "missing key #{k}"
        assert_kind_of Integer, m[k], "#{k} should be Integer"
        assert_operator m[k], :>, 0, "#{k} should be positive"
      end
    end
  end

  def test_font_metrics_linespace_is_sum
    assert_tk_app("linespace == ascent + descent") do
      m = app.font_metrics('TkDefaultFont')
      assert_equal m[:ascent] + m[:descent], m[:linespace]
    end
  end

  def test_font_metrics_with_font_spec
    assert_tk_app("font_metrics works with font spec") do
      m = app.font_metrics('Helvetica 12')
      assert_operator m[:ascent], :>, 0, "expected positive ascent"
    end
  end

  # -- measure_chars --

  def test_measure_chars_returns_hash
    assert_tk_app("measure_chars returns hash") do
      r = app.measure_chars('TkDefaultFont', 'Hello World', 50)
      assert_kind_of Hash, r
      assert r.key?(:bytes), "missing :bytes"
      assert r.key?(:width), "missing :width"
      assert_kind_of Integer, r[:bytes]
      assert_kind_of Integer, r[:width]
    end
  end

  def test_measure_chars_respects_limit
    assert_tk_app("measure_chars respects pixel limit") do
      text = 'Hello World, this is a long string for measurement'
      full_width = app.text_width('TkDefaultFont', text)
      limit = full_width / 2
      r = app.measure_chars('TkDefaultFont', text, limit)
      assert_operator r[:bytes], :<, text.bytesize, "bytes should be less than full length"
      assert_operator r[:width], :<=, limit, "width should be <= limit"
    end
  end

  def test_measure_chars_unlimited
    assert_tk_app("measure_chars with -1 returns full text") do
      text = 'Hello'
      r = app.measure_chars('TkDefaultFont', text, -1)
      assert_equal text.bytesize, r[:bytes]
    end
  end

  def test_measure_chars_whole_words
    assert_tk_app("measure_chars whole_words option") do
      text = 'Hello World Foo'
      w1 = app.text_width('TkDefaultFont', 'Hello ')
      w2 = app.text_width('TkDefaultFont', 'Hello World')
      limit = (w1 + w2) / 2

      r = app.measure_chars('TkDefaultFont', text, limit, whole_words: true)
      fitted = text[0, r[:bytes]]
      refute(fitted.include?('Wor') && !fitted.include?('World'), "expected word break, got '#{fitted}'")
    end
  end
end
