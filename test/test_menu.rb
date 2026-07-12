# frozen_string_literal: true

# Tests for menu-entry callback tracking through plain app.command() calls -
# there's no separate wrapper method to know about. app.command recognizes
# the entry-mutating shapes (add/insert/entryconfigure/delete) for a menu
# path and tracks their command: callbacks automatically; every other Tcl
# interaction goes through the same interface.
#
# Menu entries are NOT windows (only the menu itself is), entry deletion is
# silent, and survivors are renumbered internally by Tk - so tracking must
# reconcile against Tk's *live* entrycget values after every mutating call,
# never by mirroring index positions in Ruby.
#
# Interp#callback_ids is a plain reader on the interpreter's callback
# table - see also test_bind.rb.
#
# Every raw `menu` creation here passes tearoff: 0. -tearoff defaults to
# on for X11 and Windows (off on Aqua), which inserts a real entry at
# index 0 for the tear-off handle - every other index shifts down by
# one. These tests address entries by index, so without this every
# index-based assertion is off by one on a platform where tearoff
# defaults on - confirmed as the cause of a Windows-only "menu entry
# command did not fire" failure. App#menu already sets this by default;
# raw app.command(:menu, ...) does not, so it must be passed explicitly.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestMenu < Minitest::Test
  include TeekTestHelper

  def test_add_command_invoke_fires_proc
    assert_tk_app("a proc added via raw app.command should fire on invoke") do
      fired = false
      app.command(:menu, '.m1', tearoff: 0)

      app.command('.m1', :add, :command, label: 'Go', command: proc { fired = true })
      app.tcl_eval(".m1 invoke 0")

      assert fired, "menu entry command did not fire"
    end
  end

  def test_rebuild_does_not_leak_callbacks
    assert_tk_app("rebuilding a menu via raw app.command should not grow callback count") do
      app.command(:menu, '.m2', tearoff: 0)

      app.command('.m2', :add, :command, label: 'One', command: proc { })
      app.command('.m2', :add, :command, label: 'Two', command: proc { })
      app.command('.m2', :add, :separator)
      baseline = app.interp.callback_ids.length

      5.times do
        app.command('.m2', :delete, 0, :end)
        app.command('.m2', :add, :command, label: 'One', command: proc { })
        app.command('.m2', :add, :command, label: 'Two', command: proc { })
        app.command('.m2', :add, :separator)
      end

      assert_equal baseline, app.interp.callback_ids.length,
        "rebuilding the menu repeatedly should not accumulate callbacks"
    end
  end

  def test_reconciles_exactly_through_insert_entryconfigure_and_partial_delete
    assert_tk_app("insert/entryconfigure/partial-delete via raw app.command should reconcile by live value, not index") do
      app.command(:menu, '.m3', tearoff: 0)

      before = app.interp.callback_ids
      app.command('.m3', :add, :command, label: 'A', command: proc { })
      id_a = (app.interp.callback_ids - before).first
      refute_nil id_a, "adding A should register a callback"

      before = app.interp.callback_ids
      app.command('.m3', :add, :command, label: 'C', command: proc { })
      id_c = (app.interp.callback_ids - before).first
      refute_nil id_c, "adding C should register a callback"

      # entries: 0=A 1=C. Insert "B" in the middle -> 0=A 1=B 2=C.
      before = app.interp.callback_ids
      app.command('.m3', :insert, 1, :command, label: 'B', command: proc { })
      id_b = (app.interp.callback_ids - before).first
      refute_nil id_b, "inserting B should register a callback"

      # Replace C's (index 2) command in place.
      before = app.interp.callback_ids
      app.command('.m3', :entryconfigure, 2, command: proc { })
      id_c_new = (app.interp.callback_ids - before).first
      refute_nil id_c_new, "entryconfigure should register a new callback"

      refute_includes app.interp.callback_ids, id_c,
        "entryconfigure should release the callback it replaced (the gap Tkinter leaves open)"
      assert_includes app.interp.callback_ids, id_c_new,
        "entryconfigure's new callback should be tracked live"

      # Partial delete of A (index 0) only - B and C must survive untouched,
      # even though Tk renumbers them internally after the delete.
      app.command('.m3', :delete, 0)

      live = app.interp.callback_ids
      refute_includes live, id_a, "deleted entry A's callback should be released"
      assert_includes live, id_b, "surviving entry B's callback should remain tracked"
      assert_includes live, id_c_new, "surviving entry C's (replaced) callback should remain tracked"
    end
  end

  def test_destroy_releases_all_tracked_callbacks
    assert_tk_app("destroying a menu should release all its tracked callbacks, built via raw app.command") do
      app.command(:menu, '.m4', tearoff: 0)

      baseline = app.interp.callback_ids.length
      app.command('.m4', :add, :command, label: 'One', command: proc { })
      app.command('.m4', :add, :command, label: 'Two', command: proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length, "add should register two callbacks"

      app.destroy('.m4')

      assert_equal baseline, app.interp.callback_ids.length,
        "destroy should release all tracked menu-entry callbacks"
    end
  end

  def test_clear_then_destroy_does_not_double_release
    assert_tk_app("clearing a menu then destroying it should not error or double-release, via raw app.command") do
      app.command(:menu, '.m5', tearoff: 0)

      app.command('.m5', :add, :command, label: 'One', command: proc { })
      baseline = app.interp.callback_ids.length

      app.command('.m5', :delete, 0, :end)
      assert_equal baseline - 1, app.interp.callback_ids.length, "delete 0 end should release the entry"

      app.destroy('.m5') # must not raise, must not go negative / double-release

      assert_equal baseline - 1, app.interp.callback_ids.length,
        "destroying an already-cleared menu should not change callback count"
    end
  end

  def test_reused_path_after_destroy_starts_clean
    assert_tk_app("a menu rebuilt at a reused path should not inherit stale tracking, via raw app.command") do
      app.command(:menu, '.m7', tearoff: 0)
      app.command('.m7', :add, :command, label: 'Old', command: proc { })
      baseline_before_destroy = app.interp.callback_ids.length

      app.destroy('.m7')
      assert_equal baseline_before_destroy - 1, app.interp.callback_ids.length

      app.command(:menu, '.m7', tearoff: 0)
      before = app.interp.callback_ids.length
      app.command('.m7', :add, :command, label: 'New', command: proc { })

      assert_equal before + 1, app.interp.callback_ids.length,
        "the new menu at the reused path should track only its own entry"

      app.destroy('.m7')
      assert_equal before, app.interp.callback_ids.length
    end
  end
end
