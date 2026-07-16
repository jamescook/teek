# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestClipboard < Minitest::Test
  include TeekTestHelper

  def test_set_and_get_round_trips_text
    assert_tk_app("clipboard.set followed by .get should round-trip the text") do
      app.clipboard.set('hello world')

      assert_equal 'hello world', app.clipboard.get
    end
  end

  def test_set_replaces_rather_than_appends
    assert_tk_app("a second set should replace the clipboard's contents, not append to them") do
      app.clipboard.set('first')
      app.clipboard.set('second')

      assert_equal 'second', app.clipboard.get
    end
  end

  def test_set_handles_text_starting_with_a_hyphen
    assert_tk_app("set should treat a leading hyphen as literal data, not a clipboard append option") do
      app.clipboard.set('-not-an-option')

      assert_equal '-not-an-option', app.clipboard.get
    end
  end

  def test_get_returns_nil_when_the_clipboard_is_empty
    assert_tk_app("get should return nil rather than raise when nothing has been set") do
      app.clipboard.clear

      assert_nil app.clipboard.get
    end
  end

  def test_clear_empties_a_previously_set_clipboard
    assert_tk_app("clear should empty out a clipboard that already had content") do
      app.clipboard.set('something')
      app.clipboard.clear

      assert_nil app.clipboard.get
    end
  end
end
