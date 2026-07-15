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

  def test_pushing_a_not_yet_realized_lazy_panel_screen_realizes_it_then_reveals_it
    assert_tk_app("pushing a lazy: true panel screen should realize it on demand, then pack it") do
      require 'teek/ui'

      handle = nil
      session = Teek::UI.app(title: 'Screens Test') do |ui|
        ui.panel(:host) { |p| handle = p.panel(:picker, lazy: true) { |pk| pk.button(:load, text: 'Load') } }
      end
      session.run_async
      session.app.update

      assert_raises(Teek::UI::NotRealizedError) { handle.path }

      session.screens.push(:picker, handle)
      session.app.update

      assert session.app.winfo.ismapped?(handle.path)
      assert session.app.winfo.exists?("#{handle.path}.load")

      session.app.destroy
    end
  end

  def test_pushing_the_same_lazy_screen_again_after_a_pop_does_not_re_realize_it
    assert_tk_app("popping a lazy screen (which only conceals, doesn't destroy) and pushing it again should just re-reveal the same live widget, not rebuild it") do
      require 'teek/ui'

      handle = nil
      session = Teek::UI.app(title: 'Screens Test') do |ui|
        ui.panel(:host) { |p| handle = p.panel(:picker, lazy: true) { |pk| pk.button(:load, text: 'Load') } }
      end
      session.run_async
      session.app.update

      session.screens.push(:picker, handle)
      session.app.update
      first_path = handle.path

      session.screens.pop
      session.app.update
      refute session.app.winfo.ismapped?(first_path)

      session.screens.push(:picker, handle)
      session.app.update

      assert_equal first_path, handle.path, "re-pushing the same still-realized handle should reveal the SAME widget, not build a new one at a disambiguated path"
      assert session.app.winfo.ismapped?(first_path)

      session.app.destroy
    end
  end

  def test_popping_and_destroying_a_lazy_screen_releases_it_and_a_fresh_mount_can_be_pushed_again
    assert_tk_app("popping a lazy screen and destroying it should tear it down; a freshly-mounted replacement should push and realize fine") do
      require 'teek/ui'

      build_picker = ->(ui, label) {
        ui.component { |c| c.panel(:picker, lazy: true) { |p| p.button(:load, text: label).on_click { } } }
      }

      first_facade = nil
      session = Teek::UI.app(title: 'Screens Test') do |ui|
        ui.panel(:host) { |p| first_facade = build_picker.call(p, 'First') }
      end
      session.run_async
      session.app.update
      baseline = session.app.interp.callback_ids.length

      first_handle = first_facade[:picker]

      session.screens.push(:picker, first_handle) # realizes :picker on demand, since it isn't yet
      session.app.update
      assert session.app.winfo.ismapped?(first_handle.path)

      popped = session.screens.pop
      assert_same first_handle, popped
      session.app.update
      first_path = first_handle.path
      refute session.app.winfo.ismapped?(first_path), "pop alone should conceal, not destroy"

      popped.destroy!
      session.app.update
      refute session.app.winfo.exists?(first_path)
      assert_equal baseline, session.app.interp.callback_ids.length

      second_facade = nil
      session.add(:host) { |p| second_facade = build_picker.call(p, 'Second') }
      second_handle = second_facade[:picker]

      session.screens.push(:picker, second_handle)
      session.app.update

      assert session.app.winfo.ismapped?(second_handle.path)
      refute_equal first_path, second_handle.path

      session.app.destroy
    end
  end

  def test_a_child_window_style_lazy_modal_can_be_opened_and_closed_repeatedly
    assert_tk_app("a lazy: true window pushed through ModalStack should realize fresh each open, cleaning up on close") do
      require 'teek/ui'

      build_dialog = ->(ui, label) {
        ui.component { |c| c.window(:settings, lazy: true, modal: true) { |w| w.button(:ok, text: label) } }
      }

      session = Teek::UI.app(title: 'Screens Test') { |ui| ui.panel(:host) }
      session.run_async
      session.app.update
      session.modal = Teek::UI::ModalStack.new(on_enter: ->(_) { }, on_exit: -> { }, document: session.document)

      paths = []
      3.times do |i|
        facade = nil
        # each "open" builds a genuinely FRESH component (a new mount,
        # own Scope - see WidgetDSL#component) via the same incremental-
        # realize entry point any post-run dynamic UI uses - the session
        # is already realized by this point, so ordinary DSL calls
        # outside a session.add block would raise ClosedBuilderError.
        session.add(:host) { |ui2| facade = build_dialog.call(ui2, "Open #{i + 1}") }
        handle = facade[:settings]

        session.modal.push(:settings, handle)
        session.app.update
        assert session.app.winfo.ismapped?(handle.path)
        paths << handle.path

        session.modal.pop.destroy!
        session.app.update

        # destroy! unlinks the dialog's own node from :host's children,
        # not just its Tk-realized state - :host should never accumulate
        # a permanently-dead child across repeated opens.
        assert_equal 0, session.document.find(:host).children.length,
          "each mount's dialog should be fully unlinked from :host after destroy!, not just Tk-destroyed"
      end

      assert_equal paths.uniq.length, paths.length, "each open should have gotten its own distinct Tk path"

      session.app.destroy
    end
  end
end
