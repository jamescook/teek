# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Real-Tk half of Screens' coverage - pure stack bookkeeping (current/size/
# active?, a push-pop-push sequence) is covered headlessly in
# test_screens.rb; these exercise the actual reveal/conceal side effects
# (pack/pack-forget for a panel, show/hide - including modal grab/release -
# for a window) against real widgets.
class TestScreensRealTk < Minitest::Test
  include TeekTestHelper

  def test_push_reveals_a_panel_screen
    assert_tk_app("pushing a panel screen should pack it, mapping it") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Screens Test') do |ui|
        ui.panel(:picker)
        ui.panel(:emulator)
      end
      session.run_async
      session.app.update

      session.screens.push(:picker, session[:picker])
      session.app.update

      assert session.app.winfo.ismapped?(session[:picker].path)

      session.app.destroy
    end
  end

  def test_pushing_a_second_panel_screen_conceals_the_first
    assert_tk_app("pushing a second screen should pack-forget the previous one") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Screens Test') do |ui|
        ui.panel(:picker)
        ui.panel(:emulator)
      end
      session.run_async
      session.app.update

      session.screens.push(:picker, session[:picker])
      session.app.update
      session.screens.push(:emulator, session[:emulator])
      session.app.update

      refute session.app.winfo.ismapped?(session[:picker].path)
      assert session.app.winfo.ismapped?(session[:emulator].path)

      session.app.destroy
    end
  end

  def test_pop_conceals_the_current_panel_and_reveals_the_one_underneath
    assert_tk_app("pop should hide the topmost screen and re-show whatever's underneath") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Screens Test') do |ui|
        ui.panel(:picker)
        ui.panel(:emulator)
      end
      session.run_async
      session.app.update

      session.screens.push(:picker, session[:picker])
      session.screens.push(:emulator, session[:emulator])
      session.app.update

      session.screens.pop
      session.app.update

      assert session.app.winfo.ismapped?(session[:picker].path)
      refute session.app.winfo.ismapped?(session[:emulator].path)
      assert_equal :picker, session.screens.current

      session.app.destroy
    end
  end

  def test_replace_current_swaps_a_panel_screen_in_place
    assert_tk_app("replace_current should hide the old panel, show the new one, keep the same name/depth") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Screens Test') do |ui|
        ui.panel(:picker)
        ui.panel(:other_picker)
      end
      session.run_async
      session.app.update

      session.screens.push(:picker, session[:picker])
      session.app.update

      session.screens.replace_current(session[:other_picker])
      session.app.update

      refute session.app.winfo.ismapped?(session[:picker].path)
      assert session.app.winfo.ismapped?(session[:other_picker].path)
      assert_equal :picker, session.screens.current
      assert_equal 1, session.screens.size

      session.app.destroy
    end
  end

  def test_push_reveals_a_window_screen_via_show
    assert_tk_app("pushing a window screen should show it (deiconified/mapped)") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Screens Test') { |ui| ui.window(:settings) }
      session.run_async
      session.app.update

      refute session.app.winfo.ismapped?(session[:settings].path), "should start withdrawn"

      session.screens.push(:settings, session[:settings])
      session.app.update

      assert session.app.winfo.ismapped?(session[:settings].path)

      session.app.destroy
    end
  end

  def test_pop_conceals_a_window_screen_via_hide
    assert_tk_app("popping a window screen should withdraw it") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Screens Test') { |ui| ui.window(:settings) }
      session.run_async
      session.app.update

      session.screens.push(:settings, session[:settings])
      session.app.update

      session.screens.pop
      session.app.update

      refute session.app.winfo.ismapped?(session[:settings].path)

      session.app.destroy
    end
  end

  def test_modal_window_screen_grabs_when_pushed_and_releases_when_popped
    assert_tk_app("a modal: true window screen should grab on push, release on pop") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Screens Test') { |ui| ui.window(:settings, modal: true) }
      session.run_async
      session.app.update

      session.screens.push(:settings, session[:settings])
      session.app.update

      path = session[:settings].path
      assert_equal path, session.app.tcl_eval("grab current #{path}")

      session.screens.pop
      session.app.update

      assert_equal '', session.app.tcl_eval("grab current #{path}")

      session.app.destroy
    end
  end
end
