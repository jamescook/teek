# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# session.busy is a thin, realize-only delegation to Teek::App#busy (see
# teek core's own test/test_busy.rb for the underlying busy-cursor
# set/clear behavior, including exception safety). What's new to verify
# at this layer: the delegation itself (window:, block value, exception
# safety all still work through Session), and that it raises before
# realize like every other realize-only Session method.
class TestBusy < Minitest::Test
  include TeekTestHelper

  def test_busy_raises_before_realize
    assert_tk_app("session.busy should raise a clear error before realize, not queue") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Busy Test')

      assert_raises(Teek::UI::NotRealizedError) { session.busy { } }
    end
  end

  def test_busy_sets_and_clears_busy_state_and_returns_the_blocks_value
    assert_tk_app("session.busy should show the busy cursor for the duration of the block, then clear it") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Busy Test')
      session.run_async
      session.app.update

      was_busy = nil
      result = session.busy {
        was_busy = session.app.tcl_eval('tk busy status .') == '1'
        42
      }

      assert was_busy, "expected the window to be busy during the block"
      assert_equal '0', session.app.tcl_eval('tk busy status .')
      assert_equal 42, result

      session.app.destroy
    end
  end

  def test_busy_clears_on_exception
    assert_tk_app("session.busy should clear the busy cursor even if the block raises") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Busy Test')
      session.run_async
      session.app.update

      assert_raises(RuntimeError) { session.busy { raise 'boom' } }
      assert_equal '0', session.app.tcl_eval('tk busy status .')

      session.app.destroy
    end
  end

  def test_busy_works_on_a_specific_window
    assert_tk_app("session.busy's window: should target that window, not just the root") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Busy Test') { |ui| ui.window(:extra) }
      session.run_async
      session[:extra].show
      session.app.update
      extra_path = session[:extra].path

      was_busy = nil
      session.busy(window: extra_path) {
        was_busy = session.app.tcl_eval("tk busy status #{extra_path}") == '1'
      }

      assert was_busy, "expected the extra window to be busy during the block"

      session.app.destroy
    end
  end
end
