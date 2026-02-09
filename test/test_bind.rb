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
end
