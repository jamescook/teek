# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

# Behavior for the underlying wm/grab/on_close calls is already covered
# exhaustively in test_wm.rb (via App's window:-kwarg delegates) and
# test_modal.rb (via App's grab_set/grab_release/modal and Widget's
# matching delegates) - those methods now just forward to Window
# internally, confirmed still green after the refactor. This file
# verifies the new entry point itself: App#window(path) returns a real
# Window scoped to that path, and calling methods directly on it (not
# through one of the flat delegates) reaches Tcl correctly.
class TestWindow < Minitest::Test
  include TeekTestHelper

  tk_test "app.window with no args should be scoped to the root window" do
    w = app.window
    assert_equal '.', w.path
    assert_equal '.', w.to_s
  end

  tk_test "app.window(path) should be scoped to that path" do
    app.tcl_eval('toplevel .t')
    app.update

    w = app.window('.t')
    assert_equal '.t', w.path

    app.destroy('.t')
  end

  tk_test "Window#set_title/#title should round-trip without going through App" do
    w = app.window
    w.set_title('Direct via Window')
    assert_equal 'Direct via Window', w.title
  end

  tk_test "Window#set_geometry/#geometry should round-trip without going through App" do
    app.show
    app.update
    w = app.window
    w.set_geometry('320x240')
    app.update_idletasks
    assert_includes w.geometry, '320x240'
  end

  tk_test "Window#set_resizable/#resizable should round-trip without going through App" do
    w = app.window
    w.set_resizable(false, true)
    assert_equal [false, true], w.resizable
  end

  tk_test "Window#deiconify/#withdraw should map/unmap the window" do
    w = app.window
    w.deiconify
    app.update
    assert app.winfo.ismapped?('.')

    w.withdraw
    app.update
    refute app.winfo.ismapped?('.')
  end

  tk_test "Window#on_close should register a WM_DELETE_WINDOW handler" do
    app.tcl_eval('toplevel .t')
    app.update

    closed = false
    app.window('.t').on_close { closed = true }

    script = app.tcl_eval('wm protocol .t WM_DELETE_WINDOW')
    app.tcl_eval(script)

    assert closed, "on_close block registered via Window did not fire"
  end

  tk_test "Window#grab_set/#grab_release should set and clear the current grab" do
    app.tcl_eval('toplevel .t')
    app.update

    w = app.window('.t')
    w.grab_set
    assert_equal '.t', app.tcl_eval('grab current .t')

    w.grab_release
    assert_equal '', app.tcl_eval('grab current .t')

    app.destroy('.t')
  end

  tk_test "Window#modal should grab input and force focus" do
    app.tcl_eval('toplevel .t')
    app.update

    w = app.window('.t')
    w.modal

    assert_equal '.t', app.tcl_eval('grab current .t')
    assert_equal '.t', app.tcl_eval('focus')

    w.grab_release
    app.destroy('.t')
  end

  tk_test "app.wm and app.window should read back the same state - both now go through Window" do
    app.wm.set_title('Via Wm', window: '.')
    assert_equal 'Via Wm', app.window.title

    app.window.set_title('Via Window')
    assert_equal 'Via Window', app.wm.title(window: '.')
  end
end
