# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestClipboard < Minitest::Test
  include TeekTestHelper

  tk_test "clipboard.set followed by .get should round-trip the text" do
    app.clipboard.set('hello world')

    assert_equal 'hello world', app.clipboard.get
  end

  tk_test "a second set should replace the clipboard's contents, not append to them" do
    app.clipboard.set('first')
    app.clipboard.set('second')

    assert_equal 'second', app.clipboard.get
  end

  tk_test "set should treat a leading hyphen as literal data, not a clipboard append option" do
    app.clipboard.set('-not-an-option')

    assert_equal '-not-an-option', app.clipboard.get
  end

  tk_test "get should return nil rather than raise when nothing has been set" do
    app.clipboard.clear

    assert_nil app.clipboard.get
  end

  tk_test "clear should empty out a clipboard that already had content" do
    app.clipboard.set('something')
    app.clipboard.clear

    assert_nil app.clipboard.get
  end
end
