# frozen_string_literal: true

# Tests for App#appearance, App#appearance=, and App#dark?
# macOS-only (aqua windowing system) -- skips on other platforms.

require 'minitest/autorun'
require_relative 'tk_test_helper'
require_relative '../lib/teek/platform'

class TestAppearance < Minitest::Test
  include TeekTestHelper

  def setup
    skip "macOS aqua only" unless Teek.platform.darwin?
  end

  tk_test "appearance = :light should set aqua and dark? false" do
    app.appearance = :light
    assert_equal "aqua", app.appearance
    refute app.dark?, "dark? should be false in light mode"
  end

  tk_test "appearance = :dark should set darkaqua and dark? true" do
    app.appearance = :dark
    assert_equal "darkaqua", app.appearance
    assert app.dark?, "dark? should be true in dark mode"
  end

  tk_test "appearance = :auto should set auto" do
    app.appearance = :auto
    assert_equal "auto", app.appearance
  end
end
