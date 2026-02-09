# frozen_string_literal: true

# Tests for App#appearance, App#appearance=, and App#dark?
# macOS-only (aqua windowing system) -- skips on other platforms.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestAppearance < Minitest::Test
  include TeekTestHelper

  def setup
    skip "macOS aqua only" unless RUBY_PLATFORM.include?("darwin")
  end

  def test_set_light_mode
    assert_tk_app("appearance = :light should set aqua and dark? false") do
      app.appearance = :light
      assert_equal "aqua", app.appearance
      refute app.dark?, "dark? should be false in light mode"
    end
  end

  def test_set_dark_mode
    assert_tk_app("appearance = :dark should set darkaqua and dark? true") do
      app.appearance = :dark
      assert_equal "darkaqua", app.appearance
      assert app.dark?, "dark? should be true in dark mode"
    end
  end

  def test_set_auto_mode
    assert_tk_app("appearance = :auto should set auto") do
      app.appearance = :auto
      assert_equal "auto", app.appearance
    end
  end
end
