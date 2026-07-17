# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

# grab_set/grab_release are thin 1:1 wrappers over Tcl's `grab` command
# family (a separate command namespace from `wm`, so they live directly
# on App/Widget rather than inside Wm - see Wm's own doc comment).
# #modal is the composite ergonomic helper for grab-and-focus dialog
# behavior: grabs input and sets focus immediately, then releases
# either when the caller explicitly calls grab_release (their own
# dismiss/hide handler), when the window is destroyed while still
# grabbed (a <Destroy> safety net - a crash mid-modal must never leave a
# stuck grab locking out the rest of the display), or immediately if the
# optional setup block itself raises.
class TestModal < Minitest::Test
  include TeekTestHelper

  tk_test "grab_set/grab_release should set and clear the current grab" do
    app.tcl_eval('toplevel .t')
    app.update

    app.grab_set(window: '.t')
    assert_equal '.t', app.tcl_eval('grab current .t')

    app.grab_release(window: '.t')
    assert_equal '', app.tcl_eval('grab current .t')

    app.destroy('.t')
  end

  tk_test "grab_set without global: should be a local grab" do
    app.tcl_eval('toplevel .t')
    app.update

    app.grab_set(window: '.t')
    assert_equal 'local', app.tcl_eval('grab status .t')

    app.grab_release(window: '.t')
    app.destroy('.t')
  end

  tk_test "grab_set(global: true) should set a global grab" do
    app.tcl_eval('toplevel .t')
    app.update

    app.grab_set(window: '.t', global: true)
    assert_equal 'global', app.tcl_eval('grab status .t')

    app.grab_release(window: '.t')
    app.destroy('.t')
  end

  tk_test "grab_release on a window that never held the grab should not raise" do
    app.tcl_eval('toplevel .t')
    app.update

    app.grab_release(window: '.t')

    app.destroy('.t')
  end

  tk_test "modal should grab input and set focus on the window immediately" do
    app.tcl_eval('toplevel .t')
    app.update

    app.modal(window: '.t')

    assert_equal '.t', app.tcl_eval('grab current .t')
    assert_equal '.t', app.tcl_eval('focus')

    app.grab_release(window: '.t')
    app.destroy('.t')
  end

  tk_test "modal's grab should still be held after its block returns normally - it's released explicitly, not automatically" do
    app.tcl_eval('toplevel .t')
    app.update

    app.modal(window: '.t') { app.tcl_eval('wm title .t Modal') }

    assert_equal '.t', app.tcl_eval('grab current .t')

    app.grab_release(window: '.t')
    app.destroy('.t')
  end

  tk_test "modal should release the grab immediately if its setup block raises, not leave it stuck" do
    app.tcl_eval('toplevel .t')
    app.update

    error = assert_raises(RuntimeError) { app.modal(window: '.t') { raise 'boom' } }
    assert_equal 'boom', error.message

    assert_equal '', app.tcl_eval('grab current .t')

    app.destroy('.t')
  end

  tk_test "modal should release the grab if its window is destroyed without an explicit grab_release - a crash mid-modal must never leave a stuck grab" do
    app.tcl_eval('toplevel .t')
    app.update

    app.modal(window: '.t')
    assert_equal '.t', app.tcl_eval('grab current .t')

    app.destroy('.t')

    assert_equal '', app.tcl_eval('grab current')
  end

  tk_test "Widget#grab_set/#grab_release should delegate to App using the widget's own path" do
    top = app.create_widget(:toplevel, '.t')
    app.update

    top.grab_set
    assert_equal '.t', app.tcl_eval('grab current .t')

    top.grab_release
    assert_equal '', app.tcl_eval('grab current .t')

    top.destroy
  end

  tk_test "Widget#modal should delegate to App#modal using the widget's own path" do
    top = app.create_widget(:toplevel, '.t')
    app.update

    top.modal

    assert_equal '.t', app.tcl_eval('grab current .t')
    assert_equal '.t', app.tcl_eval('focus')

    top.grab_release
    top.destroy
  end
end
