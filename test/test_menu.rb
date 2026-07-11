# frozen_string_literal: true

# Tests for App#menu - building and rebuilding Tk menus without leaking the
# Ruby callback registered for each entry's `-command`. app.menu(path)
# returns a Widget (see App#create_widget) extended with Teek::MenuBehavior's
# entry methods (add_command, delete, ...).
#
# Menu entries are NOT windows (only the menu itself is), entry deletion is
# silent, and survivors are renumbered internally by Tk - so tracking must
# reconcile against Tk's *live* entrycget values after every mutating call,
# never by mirroring index positions in Ruby.
#
# app.menu(path) is a flyweight: tracking state lives on the App's
# CallbackRegistry keyed by the path string, not on the returned object, so
# callers can re-fetch app.menu(path) on every rebuild without holding a
# persistent object.
#
# Interp#callback_ids is a plain reader on the interpreter's callback
# table - see also test_bind.rb.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestMenu < Minitest::Test
  include TeekTestHelper

  def test_add_command_invoke_fires_proc
    assert_tk_app("add_command's proc should fire on invoke") do
      fired = false
      app.tcl_eval("menu .m1")
      menu = app.menu('.m1')

      menu.add_command(label: 'Go', command: proc { fired = true })
      app.tcl_eval(".m1 invoke 0")

      assert fired, "menu entry command did not fire"
    end
  end

  def test_rebuild_does_not_leak_callbacks
    assert_tk_app("rebuilding a menu should not grow callback count") do
      app.tcl_eval("menu .m2")
      menu = app.menu('.m2')

      menu.add_command(label: 'One', command: proc { })
      menu.add_command(label: 'Two', command: proc { })
      menu.add_separator
      baseline = app.interp.callback_ids.length

      5.times do
        menu.clear
        menu.add_command(label: 'One', command: proc { })
        menu.add_command(label: 'Two', command: proc { })
        menu.add_separator
      end

      assert_equal baseline, app.interp.callback_ids.length,
        "rebuilding the menu repeatedly should not accumulate callbacks"
    end
  end

  def test_reconciles_exactly_through_insert_entryconfigure_and_partial_delete
    assert_tk_app("insert/entryconfigure/partial-delete should reconcile by live value, not index") do
      app.tcl_eval("menu .m3")
      menu = app.menu('.m3')

      before = app.interp.callback_ids
      menu.add_command(label: 'A', command: proc { })
      id_a = (app.interp.callback_ids - before).first
      refute_nil id_a, "adding A should register a callback"

      before = app.interp.callback_ids
      menu.add_command(label: 'C', command: proc { })
      id_c = (app.interp.callback_ids - before).first
      refute_nil id_c, "adding C should register a callback"

      # entries: 0=A 1=C. Insert "B" in the middle -> 0=A 1=B 2=C.
      before = app.interp.callback_ids
      menu.insert(1, :command, label: 'B', command: proc { })
      id_b = (app.interp.callback_ids - before).first
      refute_nil id_b, "inserting B should register a callback"

      # Replace C's (index 2) command in place.
      before = app.interp.callback_ids
      menu.entryconfigure(2, command: proc { })
      id_c_new = (app.interp.callback_ids - before).first
      refute_nil id_c_new, "entryconfigure should register a new callback"

      refute_includes app.interp.callback_ids, id_c,
        "entryconfigure should release the callback it replaced (the gap Tkinter leaves open)"
      assert_includes app.interp.callback_ids, id_c_new,
        "entryconfigure's new callback should be tracked live"

      # Partial delete of A (index 0) only - B and C must survive untouched,
      # even though Tk renumbers them internally after the delete.
      menu.delete(0)

      live = app.interp.callback_ids
      refute_includes live, id_a, "deleted entry A's callback should be released"
      assert_includes live, id_b, "surviving entry B's callback should remain tracked"
      assert_includes live, id_c_new, "surviving entry C's (replaced) callback should remain tracked"
    end
  end

  def test_destroy_releases_all_tracked_callbacks
    assert_tk_app("destroying a menu should release all its tracked callbacks") do
      app.tcl_eval("menu .m4")
      menu = app.menu('.m4')

      baseline = app.interp.callback_ids.length
      menu.add_command(label: 'One', command: proc { })
      menu.add_command(label: 'Two', command: proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length, "add should register two callbacks"

      app.destroy('.m4')

      assert_equal baseline, app.interp.callback_ids.length,
        "destroy should release all tracked menu-entry callbacks"
    end
  end

  def test_clear_then_destroy_does_not_double_release
    assert_tk_app("clearing a menu then destroying it should not error or double-release") do
      app.tcl_eval("menu .m5")
      menu = app.menu('.m5')

      menu.add_command(label: 'One', command: proc { })
      baseline = app.interp.callback_ids.length

      menu.clear
      assert_equal baseline - 1, app.interp.callback_ids.length, "clear should release the entry"

      app.destroy('.m5') # must not raise, must not go negative / double-release

      assert_equal baseline - 1, app.interp.callback_ids.length,
        "destroying an already-cleared menu should not change callback count"
    end
  end

  def test_clear_on_empty_menu_is_safe
    assert_tk_app("clearing an empty menu should not raise") do
      app.tcl_eval("menu .m6")
      menu = app.menu('.m6')

      menu.clear # must not raise
      menu.clear # idempotent

      assert_equal '1', app.tcl_eval("winfo exists .m6"), "menu should still exist after clearing"
    end
  end

  def test_reused_path_after_destroy_starts_clean
    assert_tk_app("a menu rebuilt at a reused path should not inherit stale tracking") do
      app.tcl_eval("menu .m7")
      menu = app.menu('.m7')
      menu.add_command(label: 'Old', command: proc { })
      baseline_before_destroy = app.interp.callback_ids.length

      app.destroy('.m7')
      assert_equal baseline_before_destroy - 1, app.interp.callback_ids.length

      app.tcl_eval("menu .m7")
      menu2 = app.menu('.m7')
      before = app.interp.callback_ids.length
      menu2.add_command(label: 'New', command: proc { })

      assert_equal before + 1, app.interp.callback_ids.length,
        "the new menu at the reused path should track only its own entry"

      app.destroy('.m7')
      assert_equal before, app.interp.callback_ids.length
    end
  end

  def test_raw_command_menu_entry_warns_once_per_path
    assert_tk_app("building a menu entry via raw app.command should warn once per path, pointing at app.menu") do
      app.tcl_eval("menu .m8")

      _, err1 = capture_io do
        app.command('.m8', :add, :command, label: 'One', command: proc { })
      end
      assert_match(/app\.menu/, err1, "first raw menu add should warn and point at app.menu")

      _, err2 = capture_io do
        app.command('.m8', :add, :command, label: 'Two', command: proc { })
      end
      assert_empty err2, "second raw menu add on the same path should not warn again"
    end
  end
end
