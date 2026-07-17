# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# A bare list/text_area/table/tree/canvas auto-attaches a scrollbar
# wherever it's declared - no ui.scrollable wrapper needed. See
# Realizer#create_native_scrollable/#auto_scrollable?/#resolve_scroll.
#
# The widget is wrapped in an invisible frame (widget + scrollbar,
# gridded together) that takes over the node's own allocated path; the
# real widget lives one level deeper, at <path>.widget, which is what
# session[:name].path/.configure/events all still act on directly - see
# RealizedNode's arrange_path split. Validation that scroll: raises on an
# unsupported widget type is headless, in test_widget_dsl.rb.
class TestNativeScrollable < Minitest::Test
  include TeekTestHelper

  tk_test "ui.list should get a scrollbar with no ui.scrollable wrapper" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Native Scrollable Test') { |ui| ui.list(:items) }
    session.run_async
    session.app.update

    list_path = session[:items].path
    wrapper_path = list_path.sub(/\.widget\z/, '')
    vsb_path = "#{wrapper_path}.vsb"

    refute_equal wrapper_path, list_path, "the handle path should be the real widget, not the wrapper"
    assert_equal '1', session.app.tcl_eval("winfo exists #{vsb_path}")
    assert_equal '0', session.app.tcl_eval("winfo exists #{wrapper_path}.hsb"), "x: defaults to false"
    assert_equal "#{list_path} yview", session.app.command(vsb_path, :cget, '-command')
  end

  tk_test "Handle#configure/#on_click should still act on the real widget once auto-wrapped" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Native Scrollable Test') { |ui| ui.list(:items) }
    session.run_async
    session.app.update

    clicked = false
    session[:items].on_click { clicked = true }
    session[:items].configure(exportselection: false)
    session.app.update

    assert_equal '0', session.app.command(session[:items].path, :cget, '-exportselection')

    session.app.tcl_eval("event generate #{session[:items].path} <Button-1>")
    session.app.update

    assert clicked
  end

  tk_test "scroll: false should leave the widget exactly as it was before auto-scroll existed" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Native Scrollable Test') do |ui|
      ui.column(:panel) { |c| c.list(:items, scroll: false) }
    end
    session.run_async
    session.app.update

    assert_equal "#{session[:panel].path}.items", session[:items].path
    assert_equal '0', session.app.tcl_eval("winfo exists #{session[:items].path}.vsb")
  end

  tk_test "text_area/table/tree should get the same auto-attach treatment as list" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Native Scrollable Test') do |ui|
      ui.text_area(:notes)
      ui.table(:grid_view)
      ui.tree(:hierarchy)
    end
    session.run_async
    session.app.update

    %i[notes grid_view hierarchy].each do |name|
      wrapper = session[name].path.sub(/\.widget\z/, '')
      assert_equal '1', session.app.tcl_eval("winfo exists #{wrapper}.vsb"), "#{name} should have auto-attached a scrollbar"
    end
  end

  tk_test "canvas should default to scroll: false, unlike the other native types" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Native Scrollable Test') { |ui| ui.canvas(:board) }
    session.run_async
    session.app.update

    assert_equal '.board', session[:board].path
    assert_equal '0', session.app.tcl_eval("winfo exists .board.vsb")
  end

  tk_test "scroll: true should override canvas's own false default" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Native Scrollable Test') { |ui| ui.canvas(:board, scroll: true) }
    session.run_async
    session.app.update

    wrapper = session[:board].path.sub(/\.widget\z/, '')
    assert_equal '1', session.app.tcl_eval("winfo exists #{wrapper}.vsb")
  end

  tk_test "a canvas's own DSL children (via ui.raw) should target the real canvas, not the wrapper" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Native Scrollable Test') do |ui|
      # ui.canvas's own block yields the builder itself (not a scoped
      # Handle - see WidgetDSL's own doc comment), so the real canvas
      # handle is looked up by name via the outer `ui` instead.
      ui.canvas(:board, scroll: true) { |c| c.raw { |app| app.command(ui[:board].path, :create, :text, 10, 10, text: 'hi') } }
    end
    session.run_async
    session.app.update

    item_ids = session.app.split_list(session.app.command(session[:board].path, :find, :all))
    assert_equal 1, item_ids.length
  end

  tk_test "x: true on a bare native widget should wire a horizontal scrollbar" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Native Scrollable Test') { |ui| ui.tree(:hierarchy, x: true) }
    session.run_async
    session.app.update

    wrapper = session[:hierarchy].path.sub(/\.widget\z/, '')
    assert_equal '1', session.app.tcl_eval("winfo exists #{wrapper}.hsb")
    assert_equal "#{session[:hierarchy].path} xview", session.app.command("#{wrapper}.hsb", :cget, '-command')
  end

  tk_test "the layout should pack/place the WRAPPER, not the raw widget, inside a flow container" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Native Scrollable Test') do |ui|
      ui.column do |c|
        c.label(text: 'Header')
        c.list(:items, grow: true)
      end
    end
    session.run_async
    session.app.update

    wrapper = session[:items].path.sub(/\.widget\z/, '')
    assert_equal 'pack', session.app.tcl_eval("winfo manager #{wrapper}")
    assert session.app.winfo.ismapped?(wrapper)
  end

  tk_test "Teek::UI.app(scroll: false) should suppress auto-attach app-wide" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Native Scrollable Test', scroll: false) { |ui| ui.list(:items) }
    session.run_async
    session.app.update

    assert_equal '.items', session[:items].path
    assert_equal '0', session.app.tcl_eval("winfo exists .items.vsb")
  end

  tk_test "a widget's own scroll: true should win over the app-level default" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Native Scrollable Test', scroll: false) { |ui| ui.list(:items, scroll: true) }
    session.run_async
    session.app.update

    wrapper = session[:items].path.sub(/\.widget\z/, '')
    assert_equal '1', session.app.tcl_eval("winfo exists #{wrapper}.vsb")
  end

  tk_test "Teek::UI.auto_scroll = false should suppress the default everywhere it isn't overridden" do
    require 'teek/ui'

    # The test runner keeps one Tk worker process alive across every test
    # in this file, reusing its already-loaded Teek::UI module - so a
    # global class-level default mutated here would otherwise leak into
    # every test that runs afterward in the same process. Always restore
    # it, success or failure.
    original = Teek::UI.auto_scroll
    begin
      Teek::UI.auto_scroll = false
      session = Teek::UI.app(title: 'Native Scrollable Test') do |ui|
        ui.list(:default_items)
        ui.list(:forced_items, scroll: true)
      end
      session.run_async
      session.app.update

      assert_equal '.default_items', session[:default_items].path
      assert_equal '0', session.app.tcl_eval("winfo exists .default_items.vsb")

      forced_wrapper = session[:forced_items].path.sub(/\.widget\z/, '')
      assert_equal '1', session.app.tcl_eval("winfo exists #{forced_wrapper}.vsb")

    ensure
      Teek::UI.auto_scroll = original
    end
  end
end
