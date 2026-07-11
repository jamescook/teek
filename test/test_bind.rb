# frozen_string_literal: true

# Tests for App#bind - event binding with optional substitutions.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestBind < Minitest::Test
  include TeekTestHelper

  def test_bind_fires_callback
    assert_tk_app("bind should fire callback on event") do
      fired = false

      app.show
      app.tcl_eval("entry .e")
      app.tcl_eval("pack .e")

      app.bind('.e', 'Key-a') { fired = true }

      app.tcl_eval("focus -force .e")
      app.update
      app.tcl_eval("event generate .e <Key-a>")
      app.update

      assert fired, "callback did not fire"
    end
  end

  def test_bind_with_symbol_subs
    assert_tk_app("bind should forward substitution values") do
      received_keysym = nil

      app.show
      app.tcl_eval("entry .e")
      app.tcl_eval("pack .e")

      app.bind('.e', 'KeyPress', :keysym) { |k| received_keysym = k }

      app.tcl_eval("focus -force .e")
      app.update
      app.tcl_eval("event generate .e <KeyPress-a> -keysym a")
      app.update

      assert_equal "a", received_keysym
    end
  end

  def test_bind_with_multiple_subs
    assert_tk_app("bind should forward multiple subs") do
      got_x = nil
      got_y = nil

      app.show
      app.tcl_eval("frame .f -width 100 -height 100")
      app.tcl_eval("pack .f")
      app.update

      app.bind('.f', 'Button-1', :x, :y) { |x, y| got_x = x; got_y = y }

      app.tcl_eval("event generate .f <Button-1> -x 42 -y 17")
      app.update

      assert_equal "42", got_x
      assert_equal "17", got_y
    end
  end

  def test_bind_with_raw_sub
    assert_tk_app("bind with raw %W should forward widget path") do
      got_widget = nil

      app.show
      app.tcl_eval("entry .e2")
      app.tcl_eval("pack .e2")

      app.bind('.e2', 'FocusIn', '%W') { |w| got_widget = w }

      app.tcl_eval("focus -force .e2")
      app.update

      assert_equal ".e2", got_widget
    end
  end

  def test_bind_with_angle_brackets
    assert_tk_app("bind should not double-wrap <> in event") do
      fired = false

      app.show
      app.tcl_eval("entry .e")
      app.tcl_eval("pack .e")

      app.bind('.e', '<Key-b>') { fired = true }

      app.tcl_eval("focus -force .e")
      app.update
      app.tcl_eval("event generate .e <Key-b>")
      app.update

      assert fired, "callback did not fire with <> event string"
    end
  end

  def test_bind_on_class_tag
    assert_tk_app("bind on class tag should work") do
      fired = false

      app.show
      app.tcl_eval("entry .e")
      app.tcl_eval("pack .e")

      app.bind('Entry', 'Key-z') { fired = true }

      app.tcl_eval("focus -force .e")
      app.update
      app.tcl_eval("event generate .e <Key-z>")
      app.update

      # Clean up class binding
      app.unbind('Entry', 'Key-z')

      assert fired, "class binding did not fire"
    end
  end

  # -- command(:bind, ...) with Tk substitutions ----------------------------

  def test_command_bind_with_proc_and_percent_sub
    assert_tk_app("command(:bind) should fold %K into callback script") do
      received_keysym = nil

      app.show
      app.tcl_eval("entry .e")
      app.tcl_eval("pack .e")

      app.command(:bind, '.e', '<KeyPress>',
        proc { |k, *| received_keysym = k }, '%K')

      app.tcl_eval("focus -force .e")
      app.update
      app.tcl_eval("event generate .e <KeyPress-a> -keysym a")
      app.update

      assert_equal "a", received_keysym
    end
  end

  def test_command_bind_with_proc_and_multiple_percent_subs
    assert_tk_app("command(:bind) should fold multiple % subs into callback") do
      got_x = nil
      got_y = nil

      app.show
      app.tcl_eval("frame .f -width 100 -height 100")
      app.tcl_eval("pack .f")
      app.update

      app.command(:bind, '.f', '<Button-1>',
        proc { |x, y, *| got_x = x; got_y = y }, '%x', '%y')

      app.tcl_eval("event generate .f <Button-1> -x 42 -y 17")
      app.update

      assert_equal "42", got_x
      assert_equal "17", got_y
    end
  end

  def test_command_bind_with_proc_no_subs_still_works
    assert_tk_app("command(:bind) with proc and no subs should work") do
      fired = false

      app.show
      app.tcl_eval("entry .e")
      app.tcl_eval("pack .e")

      app.command(:bind, '.e', '<Key-c>', proc { fired = true })

      app.tcl_eval("focus -force .e")
      app.update
      app.tcl_eval("event generate .e <Key-c>")
      app.update

      assert fired, "callback did not fire"
    end
  end

  # -- unbind ---------------------------------------------------------------

  def test_unbind_removes_binding
    assert_tk_app("unbind should remove binding") do
      count = 0

      app.show
      app.tcl_eval("entry .e")
      app.tcl_eval("pack .e")

      app.bind('.e', 'Key-q') { count += 1 }

      app.tcl_eval("focus -force .e")
      app.update
      app.tcl_eval("event generate .e <Key-q>")
      app.update
      assert_equal 1, count, "binding didn't fire initially"

      app.unbind('.e', 'Key-q')

      app.tcl_eval("event generate .e <Key-q>")
      app.update
      assert_equal 1, count, "binding still fired after unbind"
    end
  end

  # -- callback cleanup (teek-6oz) -------------------------------------------
  #
  # App#bind registers a Ruby proc via Interp#register_callback. These tests
  # use Interp#callback_count (a plain reader on the interpreter's callback
  # table) to confirm those procs actually get released again, instead of
  # accumulating forever.

  def test_rebind_does_not_leak_callbacks
    assert_tk_app("rebinding the same widget+event should not grow callback count") do
      app.tcl_eval("entry .e")

      app.bind('.e', 'Key-a') { }
      baseline = app.interp.callback_count

      5.times { app.bind('.e', 'Key-a') { } }

      assert_equal baseline, app.interp.callback_count,
        "rebinding should replace, not accumulate, the registered callback"
    end
  end

  def test_unbind_releases_callback
    assert_tk_app("unbind should release the registered callback") do
      app.tcl_eval("entry .e")

      baseline = app.interp.callback_count
      app.bind('.e', 'Key-a') { }
      assert_equal baseline + 1, app.interp.callback_count, "bind should register one callback"

      app.unbind('.e', 'Key-a')

      assert_equal baseline, app.interp.callback_count, "unbind should release the callback"
    end
  end

  def test_destroy_releases_bind_callbacks
    assert_tk_app("destroying a widget should release its bind callbacks") do
      app.tcl_eval("frame .f")

      baseline = app.interp.callback_count
      app.bind('.f', 'Button-1') { }
      app.bind('.f', 'Key-a') { }
      assert_equal baseline + 2, app.interp.callback_count, "bind should register two callbacks"

      app.destroy('.f')

      assert_equal baseline, app.interp.callback_count,
        "destroy should release all bind callbacks owned by the widget"
    end
  end

  def test_destroy_releases_bind_callbacks_for_children
    assert_tk_app("destroying a widget should release bind callbacks on its descendants") do
      app.tcl_eval("frame .f2")
      app.tcl_eval("button .f2.b -text hi")

      baseline = app.interp.callback_count
      app.bind('.f2', 'Button-1') { }
      app.bind('.f2.b', 'Key-a') { }
      assert_equal baseline + 2, app.interp.callback_count, "bind should register two callbacks"

      app.destroy('.f2')

      assert_equal baseline, app.interp.callback_count,
        "destroy should recursively release descendant bind callbacks"
    end
  end

  def test_destroy_releases_bind_callbacks_without_widget_tracking
    assert_tk_app("bind cleanup should work even with track_widgets disabled") do
      app2 = Teek::App.new(track_widgets: false)
      app2.tcl_eval("frame .f3")

      baseline = app2.interp.callback_count
      app2.bind('.f3', 'Button-1') { }
      assert_equal baseline + 1, app2.interp.callback_count, "bind should register one callback"

      app2.destroy('.f3')

      assert_equal baseline, app2.interp.callback_count,
        "destroy should release bind callbacks regardless of track_widgets"
    end
  end

  def test_destroy_releases_bind_callbacks_for_menu_and_toplevel
    assert_tk_app("menu and toplevel widgets should release bind callbacks on destroy") do
      app.tcl_eval("menu .m4")
      app.tcl_eval("toplevel .t4")

      baseline = app.interp.callback_count
      app.bind('.m4', '<<MenuSelect>>') { }
      app.bind('.t4', 'Key-a') { }
      assert_equal baseline + 2, app.interp.callback_count, "bind should register two callbacks"

      app.destroy('.m4')
      app.destroy('.t4')

      assert_equal baseline, app.interp.callback_count,
        "menu/toplevel destroy should release bind callbacks"
    end
  end
end
