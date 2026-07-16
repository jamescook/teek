# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# wire_scrollbars wires -yscrollcommand/-xscrollcommand through
# Realizer#auto_hide_scrollbar instead of a plain literal string, so a
# scrollbar is grid-removed (not just left dangling and useless) whenever
# its content fully fits, and re-shown the moment it doesn't - real
# "overflow: auto" rather than a bar that's always there whether it's
# needed or not. Shared by both the native-widget auto-attach path and
# ui.scrollable's own frame case, so a couple of each is enough to prove
# the one underlying mechanism.
#
# The initial hide/show state settles via an #after_idle check (see
# Realizer#auto_hide_scrollbar's own comment - Tk only re-invokes
# -yscrollcommand on an actual fraction *change*, so an empty widget
# gaining a few rows never fires it on its own). A single
# +update_idletasks+ isn't reliably enough to flush that under Xvfb - this
# project has hit that class of timing gap before (see
# TeekTestHelper#wait_until's other callers) - so the mapped/unmapped
# assertions below poll for it instead of asserting immediately after one
# idle flush.
class TestScrollbarAutoHide < Minitest::Test
  include TeekTestHelper

  def test_scrollbar_is_hidden_when_content_fits
    assert_tk_app("a scrollbar should be grid-removed when its content doesn't overflow the visible area") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Auto-Hide Test') { |ui| ui.list(:items, height: 10) }
      session.run_async
      session.app.command(session[:items].path, :insert, :end, 'one', 'two', 'three')

      wrapper = session[:items].path.sub(/\.widget\z/, '')
      assert_equal '1', session.app.tcl_eval("winfo exists #{wrapper}.vsb"), "the scrollbar widget itself still exists"
      assert wait_until { !session.app.winfo.ismapped?("#{wrapper}.vsb") },
        "should be grid-removed once idle processing settles, since everything fits"

      session.app.destroy
    end
  end

  def test_scrollbar_is_shown_when_content_overflows
    assert_tk_app("a scrollbar should be mapped once its content overflows the visible area") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Auto-Hide Test') { |ui| ui.list(:items, height: 5) }
      session.run_async
      session.app.command(session[:items].path, :insert, :end, *(1..50).map { |i| "Item #{i}" })

      wrapper = session[:items].path.sub(/\.widget\z/, '')
      assert wait_until { session.app.winfo.ismapped?("#{wrapper}.vsb") }

      session.app.destroy
    end
  end

  def test_scrollbar_appears_once_content_grows_past_fitting
    assert_tk_app("a scrollbar hidden at realize should reappear once enough content is added later") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Auto-Hide Test') { |ui| ui.list(:items, height: 5) }
      session.run_async
      session.app.command(session[:items].path, :insert, :end, 'one', 'two')

      wrapper = session[:items].path.sub(/\.widget\z/, '')
      assert wait_until { !session.app.winfo.ismapped?("#{wrapper}.vsb") }, "should start hidden with only 2 items"

      session.app.command(session[:items].path, :insert, :end, *(1..50).map { |i| "More #{i}" })

      assert wait_until { session.app.winfo.ismapped?("#{wrapper}.vsb") }, "should reappear once content overflows"

      session.app.destroy
    end
  end

  def test_scrollbar_disappears_again_once_content_shrinks_back_to_fitting
    assert_tk_app("a visible scrollbar should hide again once enough content is removed") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Auto-Hide Test') { |ui| ui.list(:items, height: 5) }
      session.run_async
      session.app.command(session[:items].path, :insert, :end, *(1..50).map { |i| "Item #{i}" })

      wrapper = session[:items].path.sub(/\.widget\z/, '')
      assert wait_until { session.app.winfo.ismapped?("#{wrapper}.vsb") }, "should start shown with 50 items"

      session.app.command(session[:items].path, :delete, 2, :end)

      assert wait_until { !session.app.winfo.ismapped?("#{wrapper}.vsb") }, "should hide again once only 2 items remain"

      session.app.destroy
    end
  end

  def test_the_frame_case_also_auto_hides_its_scrollbar
    assert_tk_app("ui.scrollable's own canvas-driven scrollbar should auto-hide the same way") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Auto-Hide Test') do |ui|
        ui.scrollable(:region) { |s| s.column(:rows) { |c| c.button(text: 'One lone button') } }
      end
      session.run_async

      assert wait_until { !session.app.winfo.ismapped?("#{session[:region].path}.vsb") },
        "one small button shouldn't overflow the canvas's own default size"

      session.app.destroy
    end
  end

  def test_the_frame_case_shows_its_scrollbar_once_content_overflows
    assert_tk_app("ui.scrollable's canvas-driven scrollbar should appear once its content overflows") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Auto-Hide Test') do |ui|
        ui.scrollable(:region) { |s| s.column(:rows) { |c| 40.times { |i| c.button(text: "Row #{i}") } } }
      end
      session.run_async

      assert wait_until { session.app.winfo.ismapped?("#{session[:region].path}.vsb") }

      session.app.destroy
    end
  end
end
