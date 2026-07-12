# frozen_string_literal: true

# Tests for callback control flow via throw/catch.
#
# throw :teek_break    → TCL_BREAK   (stops event propagation)
# throw :teek_continue → TCL_CONTINUE
# throw :teek_return   → TCL_RETURN

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestCallbackControlFlow < Minitest::Test
  include TeekTestHelper

  def test_break_stops_event_propagation
    assert_tk_app("throw :teek_break should stop event propagation") do
      first_fired = false
      second_fired = false

      app.show
      app.tcl_eval("entry .e")
      app.tcl_eval("pack .e")

      app.bind('.e', 'Key-a') {
        first_fired = true
        throw :teek_break
      }

      app.bind('Entry', 'Key-a') { second_fired = true }

      app.tcl_eval("focus -force .e")
      app.update
      app.tcl_eval("event generate .e <Key-a>")
      app.update

      assert first_fired, "first callback did not fire"
      refute second_fired, "second callback fired despite break"

      app.unbind('Entry', 'Key-a')
    end
  end

  def test_return_does_not_crash
    assert_tk_app("throw :teek_return should not crash") do
      fired = false

      cb = app.register_callback(proc { |*|
        fired = true
        throw :teek_return
      })

      app.tcl_eval("button .b_ret -command {ruby_callback #{cb}}")
      app.tcl_eval(".b_ret invoke")

      assert fired, "callback did not fire"
    end
  end

  def test_normal_callback_unaffected
    assert_tk_app("normal callback should work") do
      result = nil

      cb = app.register_callback(proc { |*|
        result = "hello"
      })

      app.tcl_eval("button .b_norm -command {ruby_callback #{cb}}")
      app.tcl_eval(".b_norm invoke")

      assert_equal "hello", result
    end
  end

  def test_real_exception_is_tcl_error
    assert_tk_app("real exception should become Tcl error") do
      cb = app.register_callback(proc { |*|
        raise "boom"
      })

      result = app.tcl_eval("catch {ruby_callback #{cb}} errmsg")
      assert_equal "1", result

      assert_includes app.get_variable('errmsg'), "boom"
    end
  end

  # -- control-flow parity between App#bind and App#command/menu/widget-option procs --
  #
  # App#bind wraps every callback through App#register_callback, which
  # installs the catch/throw machinery above. App#command's own positional
  # and kwarg Proc handling (and the raw #tcl_value Proc path it shares
  # with any caller that isn't create_widget/Widget#command) may register
  # procs directly via Interp#register_callback instead, bypassing that
  # wrapper - so throw :teek_break there wouldn't be caught, and would
  # surface as an uncaught-throw error instead of the intended Tcl control
  # flow. These tests check each App#command-adjacent path independently.

  def test_break_in_command_positional_proc_actually_stops_propagation
    assert_tk_app("throw :teek_break in a command()-embedded positional proc should really stop propagation, not just silently error") do
      app.show
      app.tcl_eval("entry .e_pos")
      app.tcl_eval("pack .e_pos")
      first_fired = false
      second_fired = false

      app.command(:bind, '.e_pos', '<Key-a>', proc { |*|
        first_fired = true
        throw :teek_break
      })
      app.bind('Entry', 'Key-a') { second_fired = true }

      app.tcl_eval("focus -force .e_pos")
      app.update
      _, err = capture_io do
        app.tcl_eval("event generate .e_pos <Key-a>")
        app.update
      end

      assert first_fired, "first callback did not fire"
      refute second_fired, "second callback fired despite break - the throw was not turned into a real TCL_BREAK, " \
        "it just errored and got silently swallowed by bgerror"
      assert_empty err, "throw :teek_break should not produce any bgerror output - it should be real TCL_BREAK, " \
        "not an error that happens to also halt binding propagation"

      app.unbind('Entry', 'Key-a')
    end
  end

  def test_break_in_raw_command_kwarg_proc_does_not_raise
    assert_tk_app("throw :teek_break in a raw app.command kwarg proc should not raise") do
      app.tcl_eval("button .b_raw_kw")
      fired = false

      app.command('.b_raw_kw', :configure, command: proc { |*|
        fired = true
        throw :teek_break
      })

      app.tcl_eval(".b_raw_kw invoke")

      assert fired, "callback did not fire"
    end
  end

  def test_break_in_menu_entry_command_does_not_raise
    assert_tk_app("throw :teek_break in a menu entry's command should not raise") do
      fired = false
      menu = app.menu('.m_break')
      menu.command(:add, :command, label: 'Go', command: proc { |*|
        fired = true
        throw :teek_break
      })

      app.tcl_eval(".m_break invoke 0")

      assert fired, "menu command did not fire"
    end
  end

  def test_break_in_widget_option_command_does_not_raise
    assert_tk_app("throw :teek_break in a create_widget command: proc should not raise") do
      fired = false
      btn = app.create_widget('ttk::button', text: 'Go', command: proc { |*|
        fired = true
        throw :teek_break
      })

      btn.command(:invoke)

      assert fired, "button command did not fire"
    end
  end
end
