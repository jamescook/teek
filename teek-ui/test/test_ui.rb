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
    end
  end

  def test_build_constructs_no_tcl_interpreter
    assert_tk_app("building a session should not construct any Teek::App/Interp until realize") do
      require 'teek/ui'

      baseline = Teek::Interp.instance_count
      Teek::UI.app(title: 'UI Scaffold Test') { |ui| ui.document }

      assert_equal baseline, Teek::Interp.instance_count,
        "Teek::UI.app should not construct an interpreter before #realize/#run/#run_async"
    end
  end

  def test_session_exposes_a_document_before_realize
    assert_tk_app("session.document should be a real, empty Document, buildable with no interpreter") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'UI Scaffold Test')

      assert_kind_of Teek::UI::Document, session.document
      assert_equal [], session.document.root.children
    end
  end

  def test_session_app_raises_before_realize
    assert_tk_app("session.app should raise a clear error before realize") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'UI Scaffold Test')

      error = assert_raises(Teek::UI::NotRealizedError) { session.app }
      assert_match(/not realized/i, error.message)
    end
  end

  def test_session_every_and_after_raise_before_realize
    assert_tk_app("session.every/.after should raise a clear error before realize, not queue") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'UI Scaffold Test')

      assert_raises(Teek::UI::NotRealizedError) { session.every(10) { } }
      assert_raises(Teek::UI::NotRealizedError) { session.after(10) { } }
    end
  end

  def test_realize_creates_the_app_exactly_once
    assert_tk_app("realize should create the app once and return the same app on repeat calls") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'UI Scaffold Test')
      baseline = Teek::Interp.instance_count

      app1 = session.realize
      app2 = session.realize

      assert_same app1, app2, "realize should be idempotent, not build a second interpreter"
      assert_equal baseline + 1, Teek::Interp.instance_count

      session.app.destroy
    end
  end

  def test_session_app_after_realize_reflects_the_title
    assert_tk_app("session.app after realize should expose the real Teek::App with the title applied") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'UI Scaffold Test')
      session.realize

      assert_kind_of Teek::App, session.app
      assert_equal 'UI Scaffold Test', session.app.wm.title(window: '.')

      session.app.destroy
    end
  end

  def test_run_async_realizes_shows_the_window_and_returns_without_blocking
    assert_tk_app("run_async should realize, show the window, and return the session without entering mainloop") do
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

  def test_every_delegates_to_the_underlying_app_after_realize
    assert_tk_app("ui.every should delegate to App#every and actually tick, once realized") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Timers Test')
      session.run_async
      ticks = 0
      timer = session.every(10) { ticks += 1 }

      deadline = Time.now + 2
      session.app.update until ticks >= 2 || Time.now > deadline

      assert_operator ticks, :>=, 2, "ui.every's block did not tick"
      timer.cancel
      session.app.destroy
    end
  end

  def test_after_delegates_to_the_underlying_app_after_realize
    assert_tk_app("ui.after should delegate to App#after, once realized") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Timers Test')
      session.run_async
      fired = false
      session.after(10) { fired = true }

      deadline = Time.now + 2
      session.app.update until fired || Time.now > deadline

      assert fired, "ui.after's block did not fire"
      session.app.destroy
    end
  end
end
