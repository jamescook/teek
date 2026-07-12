# frozen_string_literal: true

# Tests for Teek::Winfo, the typed wrapper around Tk's `winfo` command
# family, reached via App#winfo. Grouped behind one accessor rather than
# a dozen-plus flat App methods, since `winfo` is itself one big,
# well-known Tcl command namespace - see also test_wm.rb for the sibling
# `wm` namespace's flat methods (not yet grouped, see teek-jbd).

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestWinfo < Minitest::Test
  include TeekTestHelper

  def test_width_and_height_are_integers_matching_the_requested_size
    assert_tk_app("winfo.width/height should return the actual pixel size as Integers") do
      app.show
      frame = app.create_widget('ttk::frame', width: 120, height: 80)
      frame.pack
      app.update

      assert_kind_of Integer, app.winfo.width(frame)
      assert_kind_of Integer, app.winfo.height(frame)
      assert_equal 120, app.winfo.width(frame)
      assert_equal 80, app.winfo.height(frame)
    end
  end

  def test_reqwidth_and_reqheight_are_integers
    assert_tk_app("winfo.reqwidth/reqheight should return Integers") do
      btn = app.create_widget('ttk::button', text: 'Hi')

      assert_kind_of Integer, app.winfo.reqwidth(btn)
      assert_kind_of Integer, app.winfo.reqheight(btn)
      assert_operator app.winfo.reqwidth(btn), :>, 0
    end
  end

  def test_rootx_and_rooty_are_integers
    assert_tk_app("winfo.rootx/rooty should return Integers") do
      app.show
      btn = app.create_widget('ttk::button', text: 'Hi')
      btn.pack
      app.update

      assert_kind_of Integer, app.winfo.rootx(btn)
      assert_kind_of Integer, app.winfo.rooty(btn)
    end
  end

  def test_x_and_y_are_integers
    assert_tk_app("winfo.x/y should return Integers") do
      app.show
      btn = app.create_widget('ttk::button', text: 'Hi')
      btn.pack
      app.update

      assert_kind_of Integer, app.winfo.x(btn)
      assert_kind_of Integer, app.winfo.y(btn)
    end
  end

  def test_pointerx_and_pointery_default_to_the_root_window
    assert_tk_app("winfo.pointerx/pointery should work without an explicit path") do
      assert_kind_of Integer, app.winfo.pointerx
      assert_kind_of Integer, app.winfo.pointery
    end
  end

  def test_exists_reflects_widget_lifetime
    assert_tk_app("winfo.exists? should be true for a live widget, false after destroy") do
      btn = app.create_widget('ttk::button', text: 'Hi')

      assert app.winfo.exists?(btn)

      btn.destroy
      refute app.winfo.exists?(btn)
    end
  end

  def test_exists_is_false_for_a_path_that_was_never_created
    assert_tk_app("winfo.exists? should be false for a path that was never created") do
      refute app.winfo.exists?('.never_created')
    end
  end

  def test_class_name_returns_the_tk_widget_class
    assert_tk_app("winfo.class_name should return Tk's widget class string") do
      btn = app.create_widget('ttk::button', text: 'Hi')

      assert_equal 'TButton', app.winfo.class_name(btn)
    end
  end

  def test_ismapped_reflects_whether_the_widget_is_actually_displayed
    assert_tk_app("winfo.ismapped? should be false before packing/showing, true after") do
      app.show
      btn = app.create_widget('ttk::button', text: 'Hi')

      refute app.winfo.ismapped?(btn), "an unpacked widget should not be mapped"

      btn.pack
      app.update

      assert app.winfo.ismapped?(btn), "a packed, shown widget should be mapped"
    end
  end

  def test_accepts_a_widget_object_directly_not_just_a_path_string
    assert_tk_app("winfo methods should accept a Widget directly via its to_s coercion") do
      btn = app.create_widget('ttk::button', text: 'Hi')

      assert app.winfo.exists?(btn)
      assert_equal app.winfo.exists?(btn.path), app.winfo.exists?(btn)
    end
  end
end
