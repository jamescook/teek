# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

class TestUI < Minitest::Test
  include TeekTestHelper

  def test_app_yields_and_returns_the_same_session
    assert_tk_app("Teek::UI.app should yield a session and return that same session") do
      require 'teek/ui'

      yielded = nil
      session = Teek::UI.app(title: 'UI Scaffold Test') { |ui| yielded = ui }

      assert_same session, yielded, "the block should receive the same session .app returns"
      assert_kind_of Teek::UI::Session, session

      session.app.destroy
    end
  end

  def test_session_app_is_the_escape_hatch_to_the_underlying_teek_app
    assert_tk_app("session.app should expose the real Teek::App with the title applied") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'UI Scaffold Test')

      assert_kind_of Teek::App, session.app
      assert_equal 'UI Scaffold Test', session.app.wm.title(window: '.')

      session.app.destroy
    end
  end

  def test_run_async_shows_the_window_and_returns_without_blocking
    assert_tk_app("run_async should show the window and return the session without entering mainloop") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Run Async Test')
      result = session.run_async

      assert_same session, result

      # run_async deliberately doesn't pump the event loop itself (that's the
      # documented caveat) - the deiconify it issued only becomes visible to
      # winfo after something processes events, same as a real caller would
      # need to do between REPL statements.
      session.app.update
      assert session.app.winfo.ismapped?('.'), "run_async should have shown the root window"

      session.app.destroy
    end
  end

  def test_every_delegates_to_the_underlying_app
    assert_tk_app("ui.every should delegate to App#every and actually tick") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Timers Test')
      ticks = 0
      timer = session.every(10) { ticks += 1 }

      deadline = Time.now + 2
      session.app.update until ticks >= 2 || Time.now > deadline

      assert_operator ticks, :>=, 2, "ui.every's block did not tick"
      timer.cancel
      session.app.destroy
    end
  end

  def test_after_delegates_to_the_underlying_app
    assert_tk_app("ui.after should delegate to App#after") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Timers Test')
      fired = false
      session.after(10) { fired = true }

      deadline = Time.now + 2
      session.app.update until fired || Time.now > deadline

      assert fired, "ui.after's block did not fire"
      session.app.destroy
    end
  end
end
