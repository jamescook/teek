# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Real-Tk half of ModalStack's coverage - the callback lifecycle (on_enter/
# on_exit/on_focus_change) is covered headlessly in test_modal_stack.rb;
# these exercise the actual show/hide/grab side effects against real
# ui.dialog windows.
class TestModalStackRealTk < Minitest::Test
  include TeekTestHelper

  tk_test "pushing a modal dialog should map and grab it" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'ModalStack Test') { |ui| ui.dialog(:settings) }
    session.run_async
    session.app.update

    session.modal = Teek::UI::ModalStack.new(on_enter: ->(_) { }, on_exit: -> { })
    session.modal.push(:settings, session[:settings])
    session.app.update

    path = session[:settings].path
    assert session.app.winfo.ismapped?(path)
    assert_equal path, session.app.tcl_eval("grab current #{path}")
  end

  tk_test "pushing a second dialog should withdraw/release the first and grab the second" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'ModalStack Test') do |ui|
      ui.dialog(:settings)
      ui.dialog(:replay)
    end
    session.run_async
    session.app.update

    session.modal = Teek::UI::ModalStack.new(on_enter: ->(_) { }, on_exit: -> { })
    session.modal.push(:settings, session[:settings])
    session.app.update
    session.modal.push(:replay, session[:replay])
    session.app.update

    settings_path = session[:settings].path
    replay_path = session[:replay].path

    refute session.app.winfo.ismapped?(settings_path)
    assert session.app.winfo.ismapped?(replay_path)
    assert_equal replay_path, session.app.tcl_eval("grab current #{replay_path}")
    assert_equal :replay, session.modal.current
    assert_equal 2, session.modal.size
  end

  tk_test "popping the top dialog should re-show and re-grab the one underneath" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'ModalStack Test') do |ui|
      ui.dialog(:settings)
      ui.dialog(:replay)
    end
    session.run_async
    session.app.update

    session.modal = Teek::UI::ModalStack.new(on_enter: ->(_) { }, on_exit: -> { })
    session.modal.push(:settings, session[:settings])
    session.modal.push(:replay, session[:replay])
    session.app.update

    session.modal.pop
    session.app.update

    settings_path = session[:settings].path
    replay_path = session[:replay].path

    assert session.app.winfo.ismapped?(settings_path)
    refute session.app.winfo.ismapped?(replay_path)
    assert_equal settings_path, session.app.tcl_eval("grab current #{settings_path}")
    assert_equal :settings, session.modal.current
  end

  tk_test "on_enter should fire on the first push, on_exit on the last pop" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'ModalStack Test') do |ui|
      ui.dialog(:settings)
      ui.dialog(:replay)
    end
    session.run_async
    session.app.update

    events = []
    session.modal = Teek::UI::ModalStack.new(
      on_enter: ->(name) { events << [:enter, name] },
      on_exit: -> { events << [:exit] },
      on_focus_change: ->(name) { events << [:focus, name] },
    )

    session.modal.push(:settings, session[:settings])
    session.modal.push(:replay, session[:replay])
    session.app.update
    session.modal.pop
    session.modal.pop
    session.app.update

    assert_equal [
      [:enter, :settings],
      [:focus, :settings],
      [:focus, :replay],
      [:focus, :settings],
      [:exit],
    ], events
    refute session.modal.active?
  end
end
