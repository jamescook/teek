# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestWm < Minitest::Test
  include TeekTestHelper

  # -- window_title --

  def test_set_window_title
    assert_tk_app("set_window_title sets title") do
      app.set_window_title('Hello Teek')
      assert_equal 'Hello Teek', app.window_title
    end
  end

  def test_window_title_get
    assert_tk_app("window_title returns current title") do
      app.tcl_eval('wm title . "Test Title"')
      assert_equal 'Test Title', app.window_title
    end
  end

  def test_set_window_title_on_toplevel
    assert_tk_app("set_window_title on toplevel") do
      app.tcl_eval('toplevel .t')
      app.set_window_title('Child', window: '.t')
      assert_equal 'Child', app.window_title(window: '.t')
      app.destroy('.t')
    end
  end

  # -- window_geometry --

  def test_set_window_geometry
    assert_tk_app("set_window_geometry sets geometry") do
      app.show
      app.update
      app.set_window_geometry('400x300')
      app.update_idletasks
      assert_includes app.window_geometry, '400x300'
    end
  end

  def test_window_geometry_get
    assert_tk_app("window_geometry returns geometry") do
      refute_empty app.window_geometry
    end
  end

  # -- window_resizable --

  def test_set_window_resizable
    assert_tk_app("set_window_resizable disables resize") do
      app.set_window_resizable(false, false)
      assert_equal [false, false], app.window_resizable
    end
  end

  def test_window_resizable_get
    assert_tk_app("window_resizable returns booleans") do
      app.tcl_eval('wm resizable . 1 0')
      assert_equal [true, false], app.window_resizable
    end
  end
end
