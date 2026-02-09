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
end
