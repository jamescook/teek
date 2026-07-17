# frozen_string_literal: true

# Tests for Teek::Winfo, the typed wrapper around Tk's `winfo` command
# family, reached via App#winfo. Grouped behind one accessor rather than
# a dozen-plus flat App methods, since `winfo` is itself one big,
# well-known Tcl command namespace - see also test_wm.rb for the sibling
# `wm` namespace's Teek::Wm.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestWinfo < Minitest::Test
  include TeekTestHelper

  tk_test "winfo.width/height should return the actual pixel size as Integers" do
    app.show
    frame = app.create_widget('ttk::frame', width: 120, height: 80)
    frame.pack
    app.update

    assert_kind_of Integer, app.winfo.width(frame)
    assert_kind_of Integer, app.winfo.height(frame)
    assert_equal 120, app.winfo.width(frame)
    assert_equal 80, app.winfo.height(frame)
  end

  tk_test "winfo.reqwidth/reqheight should return Integers" do
    btn = app.create_widget('ttk::button', text: 'Hi')

    assert_kind_of Integer, app.winfo.reqwidth(btn)
    assert_kind_of Integer, app.winfo.reqheight(btn)
    assert_operator app.winfo.reqwidth(btn), :>, 0
  end

  tk_test "winfo.rootx/rooty should return Integers" do
    app.show
    btn = app.create_widget('ttk::button', text: 'Hi')
    btn.pack
    app.update

    assert_kind_of Integer, app.winfo.rootx(btn)
    assert_kind_of Integer, app.winfo.rooty(btn)
  end

  tk_test "winfo.x/y should return Integers" do
    app.show
    btn = app.create_widget('ttk::button', text: 'Hi')
    btn.pack
    app.update

    assert_kind_of Integer, app.winfo.x(btn)
    assert_kind_of Integer, app.winfo.y(btn)
  end

  tk_test "winfo.pointerx/pointery should work without an explicit path" do
    assert_kind_of Integer, app.winfo.pointerx
    assert_kind_of Integer, app.winfo.pointery
  end

  tk_test "winfo.exists? should be true for a live widget, false after destroy" do
    btn = app.create_widget('ttk::button', text: 'Hi')

    assert app.winfo.exists?(btn)

    btn.destroy
    refute app.winfo.exists?(btn)
  end

  tk_test "winfo.exists? should be false for a path that was never created" do
    refute app.winfo.exists?('.never_created')
  end

  tk_test "winfo.class_name should return Tk's widget class string" do
    btn = app.create_widget('ttk::button', text: 'Hi')

    assert_equal 'TButton', app.winfo.class_name(btn)
  end

  tk_test "winfo.ismapped? should be false before packing/showing, true after" do
    app.show
    btn = app.create_widget('ttk::button', text: 'Hi')

    refute app.winfo.ismapped?(btn), "an unpacked widget should not be mapped"

    btn.pack
    app.update

    assert app.winfo.ismapped?(btn), "a packed, shown widget should be mapped"
  end

  tk_test "winfo methods should accept a Widget directly via its to_s coercion" do
    btn = app.create_widget('ttk::button', text: 'Hi')

    assert app.winfo.exists?(btn)
    assert_equal app.winfo.exists?(btn.path), app.winfo.exists?(btn)
  end
end
