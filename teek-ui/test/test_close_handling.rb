# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Under Xvfb there's no real window manager reliably sending a genuine
# WM_DELETE_WINDOW client message - these read back the script on_close
# registered via `wm protocol` and eval it directly, the same "read back
# and invoke" approach already used elsewhere in this suite (canvas item
# bindings, treeview heading commands) and in the base teek gem's own
# on_close tests.

class TestCloseHandling < Minitest::Test
  include TeekTestHelper

  def test_on_close_fires_on_a_simulated_close
    assert_tk_app("win.on_close should fire when WM_DELETE_WINDOW is simulated") do
      require 'teek/ui'

      closed = false
      session = Teek::UI.app(title: 'Close Handling Test') do |ui|
        ui.window(:settings).on_close { closed = true }
      end
      session.run_async
      session.app.update

      path = session[:settings].path
      script = session.app.tcl_eval("wm protocol #{path} WM_DELETE_WINDOW")
      session.app.tcl_eval(script)

      assert closed, "on_close block did not fire"

      session.app.destroy
    end
  end

  def test_on_close_does_not_auto_destroy_the_window
    assert_tk_app("on_close should not implicitly destroy the window - that's the block's own call") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Close Handling Test') do |ui|
        ui.window(:settings).on_close { }
      end
      session.run_async
      session.app.update

      path = session[:settings].path
      script = session.app.tcl_eval("wm protocol #{path} WM_DELETE_WINDOW")
      session.app.tcl_eval(script)

      assert session.app.winfo.exists?(path), "on_close must not destroy the window itself unless the block chooses to"

      session.app.destroy
    end
  end

  def test_on_close_block_can_choose_to_destroy_the_window
    assert_tk_app("an on_close block that destroys the window should actually close it") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Close Handling Test') do |ui|
        ui.window(:settings).on_close { session.app.destroy(session[:settings].path) }
      end
      session.run_async
      session.app.update

      path = session[:settings].path
      script = session.app.tcl_eval("wm protocol #{path} WM_DELETE_WINDOW")
      session.app.tcl_eval(script)

      refute session.app.winfo.exists?(path)

      session.app.destroy
    end
  end

  def test_rebinding_on_close_replaces_rather_than_leaks
    assert_tk_app("calling on_close again should replace the handler, not accumulate a callback") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Close Handling Test') do |ui|
        ui.window(:settings).on_close { }
      end
      session.run_async
      session.app.update
      baseline = session.app.interp.callback_ids.length

      fired_new = false
      session[:settings].on_close { fired_new = true }

      assert_equal baseline, session.app.interp.callback_ids.length,
        "rebinding on_close should replace, not accumulate, the tracked callback"

      path = session[:settings].path
      script = session.app.tcl_eval("wm protocol #{path} WM_DELETE_WINDOW")
      session.app.tcl_eval(script)

      assert fired_new, "the replaced on_close handler should be the one that fires"

      session.app.destroy
    end
  end

  def test_on_close_raises_on_a_non_window_handle
    assert_tk_app("on_close on a non-window handle should raise a clear error") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Close Handling Test') { |ui| ui.button(:go, text: 'Go') }
      session.run_async
      session.app.update

      error = assert_raises(ArgumentError) { session[:go].on_close { } }
      assert_match(/window/i, error.message)

      session.app.destroy
    end
  end
end
