# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# ui.window/ui.dialog generalize gemba's ChildWindow module (build_toplevel/
# position_near_parent/show_window/hide_window) into a DSL primitive: title/
# geometry/resizable/transient setup at realize, withdrawn by default (like
# ChildWindow's own build_toplevel), shown/hidden via Handle#show/#hide -
# which position near their parent, deiconify+raise, and (when declared
# modal: true) grab+focus/release, reusing the modal primitive already
# built on the handle rather than reimplementing any of it.
class TestManagedWindow < Minitest::Test
  include TeekTestHelper

  def test_window_is_withdrawn_by_default_after_realize
    assert_tk_app("a ui.window should start withdrawn, not visible, until shown") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings) }
      session.run_async
      session.app.update

      refute session.app.winfo.ismapped?(session[:settings].path),
        "a freshly realized window should be withdrawn by default"

      session.app.destroy
    end
  end

  def test_title_and_geometry_are_applied_at_realize
    assert_tk_app("title:/geometry: opts should be applied via wm at realize") do
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
  end

  def test_resizable_opt_accepts_a_single_boolean_for_both_axes
    assert_tk_app("resizable: false should set both width and height non-resizable") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Managed Window Test') do |ui|
        ui.window(:settings, resizable: false)
      end
      session.run_async
      session.app.update

      assert_equal '0 0', session.app.tcl_eval("wm resizable #{session[:settings].path}")

      session.app.destroy
    end
  end

  def test_resizable_opt_accepts_a_width_height_pair
    assert_tk_app("resizable: [true, false] should set width/height independently") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Managed Window Test') do |ui|
        ui.window(:settings, resizable: [true, false])
      end
      session.run_async
      session.app.update

      assert_equal '1 0', session.app.tcl_eval("wm resizable #{session[:settings].path}")

      session.app.destroy
    end
  end

  def test_window_defaults_to_leaving_resizable_untouched
    assert_tk_app("without a resizable: opt, Tk's own default (resizable both ways) should apply") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings) }
      session.run_async
      session.app.update

      assert_equal '1 1', session.app.tcl_eval("wm resizable #{session[:settings].path}")

      session.app.destroy
    end
  end

  def test_window_is_transient_to_its_parent_by_default
    assert_tk_app("a top-level ui.window should be transient to the root window by default") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings) }
      session.run_async
      session.app.update

      assert_equal '.', session.app.tcl_eval("wm transient #{session[:settings].path}")

      session.app.destroy
    end
  end

  def test_nested_window_is_transient_to_its_enclosing_window_not_the_root
    assert_tk_app("a ui.window nested inside another ui.window should be transient to that window") do
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
  end

  def test_transient_false_disables_it
    assert_tk_app("transient: false should leave the window with no transient parent") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Managed Window Test') do |ui|
        ui.window(:settings, transient: false)
      end
      session.run_async
      session.app.update

      assert_equal '', session.app.tcl_eval("wm transient #{session[:settings].path}")

      session.app.destroy
    end
  end

  def test_show_deiconifies_raises_and_positions_near_its_parent
    assert_tk_app("show should map the window and position it just to the right of its parent") do
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
  end

  def test_hide_withdraws_the_window
    assert_tk_app("hide should withdraw a previously shown window") do
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
  end

  def test_show_grabs_and_focuses_when_declared_modal
    assert_tk_app("show should grab input and force focus when the window was declared modal: true") do
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
  end

  def test_show_does_not_grab_when_not_declared_modal
    assert_tk_app("show should not grab input for an ordinary (non-modal) window") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Managed Window Test') { |ui| ui.window(:settings) }
      session.run_async
      session.app.update

      session[:settings].show
      session.app.update

      assert_equal '', session.app.tcl_eval("grab current #{session[:settings].path}")

      session.app.destroy
    end
  end

  def test_hide_releases_the_grab_for_a_modal_window
    assert_tk_app("hide should release the grab a modal show set") do
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
  end

  def test_dialog_defaults_to_modal_and_non_resizable
    assert_tk_app("ui.dialog should default to modal: true, resizable: false") do
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
  end

  def test_dialog_defaults_are_overridable
    assert_tk_app("ui.dialog's modal:/resizable: defaults should still be overridable") do
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
  end

  def test_show_and_hide_raise_on_a_non_window_handle
    assert_tk_app("show/hide on a non-window handle should raise a clear error") do
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
end
