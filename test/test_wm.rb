# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestWm < Minitest::Test
  include TeekTestHelper

  # -- window_title --

  def test_set_window_title
    assert_tk_app("set_window_title sets title", method(:app_set_window_title))
  end

  def app_set_window_title
    app.set_window_title('Hello Teek')
    result = app.window_title
    raise "expected 'Hello Teek', got '#{result}'" unless result == 'Hello Teek'
  end

  def test_window_title_get
    assert_tk_app("window_title returns current title", method(:app_window_title_get))
  end

  def app_window_title_get
    app.tcl_eval('wm title . "Test Title"')
    result = app.window_title
    raise "expected 'Test Title', got '#{result}'" unless result == 'Test Title'
  end

  def test_set_window_title_on_toplevel
    assert_tk_app("set_window_title on toplevel", method(:app_set_window_title_on_toplevel))
  end

  def app_set_window_title_on_toplevel
    app.tcl_eval('toplevel .t')
    app.set_window_title('Child', window: '.t')
    result = app.window_title(window: '.t')
    raise "expected 'Child', got '#{result}'" unless result == 'Child'
    app.destroy('.t')
  end

  # -- window_geometry --

  def test_set_window_geometry
    assert_tk_app("set_window_geometry sets geometry", method(:app_set_window_geometry))
  end

  def app_set_window_geometry
    app.show
    app.update
    app.set_window_geometry('400x300')
    app.update_idletasks
    result = app.window_geometry
    raise "expected '400x300' in geometry, got '#{result}'" unless result.include?('400x300')
  end

  def test_window_geometry_get
    assert_tk_app("window_geometry returns geometry", method(:app_window_geometry_get))
  end

  def app_window_geometry_get
    result = app.window_geometry
    raise "expected non-empty geometry, got '#{result}'" if result.empty?
  end

  # -- window_resizable --

  def test_set_window_resizable
    assert_tk_app("set_window_resizable disables resize", method(:app_set_window_resizable))
  end

  def app_set_window_resizable
    app.set_window_resizable(false, false)
    w, h = app.window_resizable
    raise "expected [false, false], got [#{w}, #{h}]" unless w == false && h == false
  end

  def test_window_resizable_get
    assert_tk_app("window_resizable returns booleans", method(:app_window_resizable_get))
  end

  def app_window_resizable_get
    app.tcl_eval('wm resizable . 1 0')
    w, h = app.window_resizable
    raise "expected [true, false], got [#{w}, #{h}]" unless w == true && h == false
  end
end
