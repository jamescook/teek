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
    assert_tk_app("appearance = :light should set aqua and dark? false", method(:app_set_light_mode))
  end

  def app_set_light_mode
    app.appearance = :light
    raise "expected aqua, got #{app.appearance}" unless app.appearance == "aqua"
    raise "dark? should be false in light mode" if app.dark?
  end

  def test_set_dark_mode
    assert_tk_app("appearance = :dark should set darkaqua and dark? true", method(:app_set_dark_mode))
  end

  def app_set_dark_mode
    app.appearance = :dark
    raise "expected darkaqua, got #{app.appearance}" unless app.appearance == "darkaqua"
    raise "dark? should be true in dark mode" unless app.dark?
  end

  def test_set_auto_mode
    assert_tk_app("appearance = :auto should set auto", method(:app_set_auto_mode))
  end

  def app_set_auto_mode
    app.appearance = :auto
    raise "expected auto, got #{app.appearance}" unless app.appearance == "auto"
  end
end
