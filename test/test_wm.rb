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

  # -- interp.window_geometry (C-level Tk_GetRootCoords + Tk_Width/Tk_Height) --

  def test_interp_window_geometry_returns_four_integers
    assert_tk_app("interp.window_geometry returns [x, y, w, h]") do
      app.show
      app.set_window_geometry('320x240')
      app.update
      result = app.interp.window_geometry('.')
      assert_kind_of Array, result
      assert_equal 4, result.length
      result.each { |v| assert_kind_of Integer, v }
      # Width/height should match what we requested
      _x, _y, w, h = result
      assert_equal 320, w
      assert_equal 240, h
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

  # -- on_close --
  #
  # Under Xvfb there's no real window manager reliably sending a genuine
  # WM_DELETE_WINDOW client message, so these read back the script
  # on_close registered via `wm protocol` and eval it directly - the
  # same "read back and invoke" approach already used for treeview
  # heading commands and canvas item bindings elsewhere in this suite.

  def test_on_close_fires_on_the_root_window_by_default
    assert_tk_app("on_close with no window: should register on the root window") do
      fired = false
      app.on_close { fired = true }

      script = app.tcl_eval('wm protocol . WM_DELETE_WINDOW')
      app.tcl_eval(script)

      assert fired, "on_close block did not fire"
    end
  end

  def test_on_close_does_not_auto_destroy_the_window
    assert_tk_app("on_close should not implicitly destroy the window - that's the block's call") do
      app.tcl_eval('toplevel .t_no_destroy')
      app.on_close(window: '.t_no_destroy') { }

      script = app.tcl_eval('wm protocol .t_no_destroy WM_DELETE_WINDOW')
      app.tcl_eval(script)

      assert_equal '1', app.tcl_eval('winfo exists .t_no_destroy'),
        "on_close must not destroy the window itself - only the block should decide that"
      app.destroy('.t_no_destroy')
    end
  end

  def test_on_close_block_can_choose_to_destroy_the_window
    assert_tk_app("an on_close block that calls destroy should actually close the window") do
      app.tcl_eval('toplevel .t_destroy')
      app.on_close(window: '.t_destroy') { app.destroy('.t_destroy') }

      script = app.tcl_eval('wm protocol .t_destroy WM_DELETE_WINDOW')
      app.tcl_eval(script)

      assert_equal '0', app.tcl_eval('winfo exists .t_destroy')
    end
  end

  def test_on_close_releases_its_callback_when_the_window_is_destroyed
    assert_tk_app("destroying a window should release its on_close callback") do
      app.tcl_eval('toplevel .t_release')
      baseline = app.interp.callback_ids.length

      app.on_close(window: '.t_release') { }
      assert_equal baseline + 1, app.interp.callback_ids.length

      app.destroy('.t_release')

      assert_equal baseline, app.interp.callback_ids.length,
        "destroying the window should release the on_close callback"
    end
  end

  def test_on_close_rebind_does_not_leak_callbacks
    assert_tk_app("calling on_close again for the same window should replace, not accumulate") do
      app.tcl_eval('toplevel .t_rebind')
      baseline = app.interp.callback_ids.length

      app.on_close(window: '.t_rebind') { }
      5.times { app.on_close(window: '.t_rebind') { } }

      assert_equal baseline + 1, app.interp.callback_ids.length,
        "rebinding on_close should replace, not accumulate, the registered callback"
      app.destroy('.t_rebind')
    end
  end

  def test_on_close_multiple_toplevels_are_independent
    assert_tk_app("two toplevels should each get their own independent on_close handler") do
      app.tcl_eval('toplevel .t_a')
      app.tcl_eval('toplevel .t_b')
      fired_a = false
      fired_b = false

      app.on_close(window: '.t_a') { fired_a = true }
      app.on_close(window: '.t_b') { fired_b = true }

      script_a = app.tcl_eval('wm protocol .t_a WM_DELETE_WINDOW')
      app.tcl_eval(script_a)

      assert fired_a, ".t_a's on_close should have fired"
      refute fired_b, ".t_b's on_close should not have fired from .t_a's close"

      app.destroy('.t_a')
      app.destroy('.t_b')
    end
  end

  # -- Teek::Wm (app.wm) --
  #
  # Grouped, typed wrappers for the `wm` command family, mirroring
  # Tcl's own subcommand names - see test_winfo.rb for the sibling
  # `winfo` namespace. App's existing set_window_title/window_geometry/
  # etc. above are thin delegates to these now, kept as-is so nothing
  # that already uses them (including gemba) needs to change.

  def test_wm_title_get_and_set
    assert_tk_app("app.wm.set_title/#title should get and set the window title") do
      app.wm.set_title('Hello via wm')
      assert_equal 'Hello via wm', app.wm.title
    end
  end

  def test_wm_title_with_unbalanced_brace_reaches_tk_verbatim
    assert_tk_app("app.wm.set_title should round-trip a title with an unbalanced brace") do
      value = 'Title } with brace'
      app.wm.set_title(value)

      assert_equal value, app.wm.title
    end
  end

  def test_wm_title_on_a_toplevel
    assert_tk_app("app.wm.set_title/#title should accept a window: other than the root") do
      app.tcl_eval('toplevel .t_wm_title')
      app.wm.set_title('Child', window: '.t_wm_title')

      assert_equal 'Child', app.wm.title(window: '.t_wm_title')
      app.destroy('.t_wm_title')
    end
  end

  def test_wm_geometry_get_and_set
    assert_tk_app("app.wm.set_geometry/#geometry should get and set the window geometry") do
      app.show
      app.update
      app.wm.set_geometry('400x300')
      app.update_idletasks

      assert_includes app.wm.geometry, '400x300'
    end
  end

  def test_wm_resizable_get_and_set
    assert_tk_app("app.wm.set_resizable/#resizable should get and set resizable flags") do
      app.wm.set_resizable(false, true)

      assert_equal [false, true], app.wm.resizable
    end
  end

  def test_wm_deiconify_and_withdraw
    assert_tk_app("app.wm.deiconify/#withdraw should map/unmap the window") do
      app.wm.deiconify
      app.update

      assert app.winfo.ismapped?('.')

      app.wm.withdraw
      app.update

      refute app.winfo.ismapped?('.')
    end
  end

  # Regression guard: set_window_title used to build "wm title . {#{title}}"
  # via raw string interpolation, which broke on an unbalanced brace - it
  # now delegates to app.wm.set_title (tcl_invoke-based), fixing this for
  # free.
  def test_set_window_title_handles_an_unbalanced_brace
    assert_tk_app("the flat set_window_title should also round-trip an unbalanced brace now") do
      value = 'Title } with brace'
      app.set_window_title(value)

      assert_equal value, app.window_title
    end
  end
end
