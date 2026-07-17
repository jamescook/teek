# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# ui.window/ui.dialog are a DSL primitive for managed toplevels: title/
# geometry/resizable/transient setup at realize, withdrawn by default,
# shown/hidden via Handle#show/#hide - which position near their parent,
# deiconify+raise, and (when declared modal: true) grab+focus/release,
# reusing the modal primitive already built on the handle rather than
# reimplementing any of it.
class TestManagedWindow < Minitest::Test
  include TeekTestHelper

  tk_test "a ui.window should start withdrawn, not visible, until shown" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings) }
    session.run_async
    session.app.update

    refute session.app.winfo.ismapped?(session[:settings].path),
      "a freshly realized window should be withdrawn by default"

    session.app.destroy
  end

  tk_test "title:/geometry: opts should be applied via wm at realize" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') do |ui|
      ui.window(:settings, title: 'Settings', geometry: '300x200')
    end
    session.run_async
    session.app.update

    path = session[:settings].path
    assert_equal 'Settings', session.app.tcl_eval("wm title #{path}")

    # geometry requested while withdrawn doesn't reliably read back until
    # the window is actually mapped and idle tasks run - same reason
    # base teek's own test_set_window_geometry shows the window first.
    session[:settings].show
    session.app.update_idletasks
    assert_includes session.app.tcl_eval("wm geometry #{path}"), '300x200'

    session.app.destroy
  end

  tk_test "resizable: false should set both width and height non-resizable" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') do |ui|
      ui.window(:settings, resizable: false)
    end
    session.run_async
    session.app.update

    assert_equal '0 0', session.app.tcl_eval("wm resizable #{session[:settings].path}")

    session.app.destroy
  end

  tk_test "resizable: [true, false] should set width/height independently" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') do |ui|
      ui.window(:settings, resizable: [true, false])
    end
    session.run_async
    session.app.update

    assert_equal '1 0', session.app.tcl_eval("wm resizable #{session[:settings].path}")

    session.app.destroy
  end

  tk_test "without a resizable: opt, Tk's own default (resizable both ways) should apply" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings) }
    session.run_async
    session.app.update

    assert_equal '1 1', session.app.tcl_eval("wm resizable #{session[:settings].path}")

    session.app.destroy
  end

  tk_test "a top-level ui.window should be transient to the root window by default" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings) }
    session.run_async
    session.app.update

    assert_equal '.', session.app.tcl_eval("wm transient #{session[:settings].path}")

    session.app.destroy
  end

  tk_test "a ui.window nested inside another ui.window should be transient to that window" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') do |ui|
      ui.window(:outer) { |o| o.window(:inner) }
    end
    session.run_async
    session.app.update

    outer_path = session[:outer].path
    inner_path = session[:inner].path
    assert_equal outer_path, session.app.tcl_eval("wm transient #{inner_path}")

    session.app.destroy
  end

  tk_test "transient: false should leave the window with no transient parent" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') do |ui|
      ui.window(:settings, transient: false)
    end
    session.run_async
    session.app.update

    assert_equal '', session.app.tcl_eval("wm transient #{session[:settings].path}")

    session.app.destroy
  end

  tk_test "show should map the window and position it just to the right of its parent" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings) }
    session.run_async
    session.app.update

    root_x, root_y, root_w, = session.app.interp.window_geometry('.')
    session[:settings].show
    session.app.update

    assert session.app.winfo.ismapped?(session[:settings].path)
    settings_x, settings_y, = session.app.interp.window_geometry(session[:settings].path)
    assert_equal root_x + root_w + 12, settings_x
    assert_equal root_y, settings_y

    session.app.destroy
  end

  tk_test "hide should withdraw a previously shown window" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings) }
    session.run_async
    session.app.update

    session[:settings].show
    session.app.update
    assert session.app.winfo.ismapped?(session[:settings].path)

    session[:settings].hide
    session.app.update
    refute session.app.winfo.ismapped?(session[:settings].path)

    session.app.destroy
  end

  tk_test "show should grab input and force focus when the window was declared modal: true" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings, modal: true) }
    session.run_async
    session.app.update

    session[:settings].show
    session.app.update

    path = session[:settings].path
    assert_equal path, session.app.tcl_eval("grab current #{path}")
    assert_equal path, session.app.tcl_eval('focus')

    session.app.destroy
  end

  tk_test "show should not grab input for an ordinary (non-modal) window" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings) }
    session.run_async
    session.app.update

    session[:settings].show
    session.app.update

    assert_equal '', session.app.tcl_eval("grab current #{session[:settings].path}")

    session.app.destroy
  end

  tk_test "hide should release the grab a modal show set" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings, modal: true) }
    session.run_async
    session.app.update

    session[:settings].show
    session.app.update
    path = session[:settings].path
    assert_equal path, session.app.tcl_eval("grab current #{path}")

    session[:settings].hide
    session.app.update
    assert_equal '', session.app.tcl_eval("grab current #{path}")

    session.app.destroy
  end

  tk_test "ui.dialog should default to modal: true, resizable: false" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.dialog(:confirm) }
    session.run_async
    session.app.update

    path = session[:confirm].path
    assert_equal :window, session[:confirm].type
    assert_equal '0 0', session.app.tcl_eval("wm resizable #{path}")

    session[:confirm].show
    session.app.update
    assert_equal path, session.app.tcl_eval("grab current #{path}")

    session.app.destroy
  end

  tk_test "ui.dialog's modal:/resizable: defaults should still be overridable" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') do |ui|
      ui.dialog(:confirm, modal: false, resizable: true)
    end
    session.run_async
    session.app.update

    path = session[:confirm].path
    assert_equal '1 1', session.app.tcl_eval("wm resizable #{path}")

    session[:confirm].show
    session.app.update
    assert_equal '', session.app.tcl_eval("grab current #{path}")

    session.app.destroy
  end

  tk_test "show/hide on a non-window handle should raise a clear error" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.button(:go, text: 'Go') }
    session.run_async
    session.app.update

    show_error = assert_raises(ArgumentError) { session[:go].show }
    assert_match(/window/i, show_error.message)

    hide_error = assert_raises(ArgumentError) { session[:go].hide }
    assert_match(/window/i, hide_error.message)

    session.app.destroy
  end
end
