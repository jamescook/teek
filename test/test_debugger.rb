# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestDebugger < Minitest::Test
  include TeekTestHelper

  def test_debugger_creates_window
    assert_tk_app("debugger creates window") do
      app = Teek::App.new(debug: true)
      assert app.debugger, "debugger not created"
      assert app.debugger.interp, "debugger interp missing"

      assert_equal "1", app.tcl_eval('winfo exists .teek_debug')
      assert_equal "1", app.tcl_eval('winfo exists .teek_debug.nb')
    end
  end

  def test_debugger_tracks_widgets
    assert_tk_app("debugger tracks widget creation") do
      app = Teek::App.new(debug: true)

      app.show
      app.tcl_eval('ttk::frame .f')
      app.tcl_eval('ttk::button .f.btn -text Hello')
      app.update

      assert_equal "1", app.tcl_eval('.teek_debug.nb.widgets.tree exists .f')
      assert_equal "1", app.tcl_eval('.teek_debug.nb.widgets.tree exists .f.btn')
    end
  end

  def test_debugger_tracks_destroy
    assert_tk_app("debugger tracks widget destruction") do
      app = Teek::App.new(debug: true)

      app.show
      app.tcl_eval('ttk::button .btn -text Bye')
      app.update

      assert_equal "1", app.tcl_eval('.teek_debug.nb.widgets.tree exists .btn')

      app.destroy('.btn')
      app.update

      assert_equal "0", app.tcl_eval('.teek_debug.nb.widgets.tree exists .btn')
    end
  end

  def test_debugger_show_hide
    assert_tk_app("debugger show/hide") do
      app = Teek::App.new(debug: true)

      app.debugger.hide
      assert_equal "withdrawn", app.tcl_eval('wm state .teek_debug')

      app.debugger.show
      app.update
      assert_equal "normal", app.tcl_eval('wm state .teek_debug')
    end
  end

  def test_debugger_widgets_not_tracked
    assert_tk_app("debugger widgets filtered") do
      app = Teek::App.new(debug: true)

      app.widgets.each_key do |path|
        refute path.start_with?('.teek_debug'), "debugger widget #{path} leaked into app.widgets"
      end
    end
  end

  def test_debugger_tree_select
    assert_tk_app("tree select shows widget config") do
      app = Teek::App.new(debug: true)
      app.show
      app.tcl_eval('ttk::button .btn -text Hello')
      app.update

      tree = '.teek_debug.nb.widgets.tree'
      app.tcl_eval("#{tree} selection set .btn")
      app.tcl_eval("event generate #{tree} <<TreeviewSelect>>")
      app.update

      detail = app.tcl_eval('.teek_debug.nb.widgets.detail.text get 1.0 end').strip
      assert_includes detail, '.btn'
    end
  end

  def test_debugger_tree_select_destroyed_widget
    assert_tk_app("tree select handles destroyed widget") do
      app = Teek::App.new(debug: true)
      app.show
      app.tcl_eval('ttk::button .gone -text Bye')
      app.update

      tree = '.teek_debug.nb.widgets.tree'
      # Destroy widget but leave tree item
      app.tcl_eval('destroy .gone')
      app.update

      # Select the stale tree item
      if app.tcl_eval("#{tree} exists .gone") == "1"
        app.tcl_eval("#{tree} selection set .gone")
        app.tcl_eval("event generate #{tree} <<TreeviewSelect>>")
        app.update

        detail = app.tcl_eval('.teek_debug.nb.widgets.detail.text get 1.0 end').strip
        assert_includes detail, 'no longer exists'
      end
    end
  end

  def test_debugger_watch_variable
    assert_tk_app("watch add/record/remove") do
      app = Teek::App.new(debug: true)
      app.set_variable('mywatch', 'initial')
      app.update

      # Add watch via public API
      app.debugger.add_watch('mywatch')

      # Watch tree shows the variable
      watch_tree = '.teek_debug.nb.watches.tree'
      assert_equal "1", app.tcl_eval("#{watch_tree} exists watch_mywatch")

      # Tcl trace fires on change
      app.set_variable('mywatch', 'changed')
      app.update

      vals = Teek.split_list(app.tcl_eval("#{watch_tree} item watch_mywatch -values"))
      assert_equal 'changed', vals[0]

      # Remove watch via public API
      app.debugger.remove_watch('mywatch')
      assert_equal "0", app.tcl_eval("#{watch_tree} exists watch_mywatch")
    end
  end

  def test_debugger_watch_ui_toggle
    assert_tk_app("watch UI toggles help/tree") do
      app = Teek::App.new(debug: true)
      app.tcl_eval('.teek_debug.nb select .teek_debug.nb.watches')
      app.update

      # No watches — help label should be visible
      assert_equal "1", app.tcl_eval('winfo ismapped .teek_debug.nb.watches.help')

      # Add a watch — tree should appear
      app.set_variable('wvar', 'val')
      app.debugger.add_watch('wvar')
      app.update

      assert_equal "1", app.tcl_eval('winfo ismapped .teek_debug.nb.watches.tree')

      # Remove — help should return
      app.debugger.remove_watch('wvar')
      app.update

      assert_equal "1", app.tcl_eval('winfo ismapped .teek_debug.nb.watches.help')
    end
  end

  def test_debugger_watch_select_shows_history
    assert_tk_app("watch select shows history") do
      app = Teek::App.new(debug: true)
      app.set_variable('hvar', 'v1')
      app.debugger.add_watch('hvar')

      # Tcl trace records each change
      app.set_variable('hvar', 'v2')
      app.update
      app.set_variable('hvar', 'v3')
      app.update

      # Select the watch item in the tree
      watch_tree = '.teek_debug.nb.watches.tree'
      app.tcl_eval("#{watch_tree} selection set watch_hvar")
      app.tcl_eval("event generate #{watch_tree} <<TreeviewSelect>>")
      app.update

      history = app.tcl_eval('.teek_debug.nb.watches.history get 1.0 end').strip
      assert_includes history, 'hvar'
    end
  end

  def test_debugger_unwatch_via_context_menu
    assert_tk_app("unwatch from watch tree context menu") do
      app = Teek::App.new(debug: true)
      app.set_variable('uvar', 'val')
      app.debugger.add_watch('uvar')
      app.update

      # Select the watch, then invoke the Unwatch menu item
      watch_tree = '.teek_debug.nb.watches.tree'
      app.tcl_eval("#{watch_tree} selection set watch_uvar")
      app.tcl_eval('.teek_debug.nb.watches.ctx invoke 0')
      app.update

      assert_equal "0", app.tcl_eval("#{watch_tree} exists watch_uvar")
    end
  end

  def test_debugger_variables_refresh_button
    assert_tk_app("refresh button updates variables tab") do
      app = Teek::App.new(debug: true)
      app.set_variable('btnvar', 'before')
      app.update

      # Click Refresh to populate
      app.tcl_eval('.teek_debug.nb.vars.toolbar.refresh invoke')
      app.update

      vars_tree = '.teek_debug.nb.vars.tree'
      assert_equal "1", app.tcl_eval("#{vars_tree} exists v:btnvar")

      # Change value and refresh again
      app.set_variable('btnvar', 'after')
      app.tcl_eval('.teek_debug.nb.vars.toolbar.refresh invoke')
      app.update

      vals = Teek.split_list(app.tcl_eval("#{vars_tree} item v:btnvar -values"))
      assert_equal 'after', vals[0]
    end
  end

  def test_debugger_watch_via_double_click
    assert_tk_app("double-click variable to watch") do
      app = Teek::App.new(debug: true)
      app.set_variable('dblvar', 'hello')
      app.update

      # Refresh variables tab so dblvar appears
      app.tcl_eval('.teek_debug.nb.vars.toolbar.refresh invoke')
      app.update

      # Select the variable and double-click to watch
      vars_tree = '.teek_debug.nb.vars.tree'
      app.tcl_eval("#{vars_tree} selection set v:dblvar")
      app.tcl_eval("event generate #{vars_tree} <ButtonPress-1>")
      app.tcl_eval("event generate #{vars_tree} <ButtonRelease-1>")
      app.tcl_eval("event generate #{vars_tree} <ButtonPress-1>")
      app.tcl_eval("event generate #{vars_tree} <ButtonRelease-1>")
      app.update

      # Should now appear in the watches tree
      watch_tree = '.teek_debug.nb.watches.tree'
      assert_equal "1", app.tcl_eval("#{watch_tree} exists watch_dblvar")
    end
  end

  def test_debugger_auto_refresh_updates_variables
    assert_tk_app("auto-refresh picks up variable changes") do
      app = Teek::App.new(debug: true)
      app.set_variable('autovar', 'original')
      app.update

      # Initial refresh
      app.tcl_eval('.teek_debug.nb.vars.toolbar.refresh invoke')
      app.update

      vars_tree = '.teek_debug.nb.vars.tree'
      assert_equal "1", app.tcl_eval("#{vars_tree} exists v:autovar")

      # Change value, then wait for auto-refresh (fires every 1s)
      app.set_variable('autovar', 'updated')
      result = wait_for_display('updated', timeout: 2.0) do
        Teek.split_list(app.tcl_eval("#{vars_tree} item v:autovar -values"))[0]
      end
      assert_equal 'updated', result
    end
  end
end
