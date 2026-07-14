# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# ui.scrollable auto-wires a scrollbar (ttk::scrollbar) so app code never
# writes -yscrollcommand/-xscrollcommand/scrollbar wiring itself. Two
# cases: a single natively-scrollable child (list/text_area/table/tree/
# canvas) gets a scrollbar hooked straight to it; anything else (no
# children, several, or a plain container) is wrapped in a canvas +
# embedded viewport frame instead - see Realizer#create_scrollable.
class TestScrollable < Minitest::Test
  include TeekTestHelper

  def test_native_child_gets_a_vertical_scrollbar_wired_to_it_by_default
    assert_tk_app("a scrollable list should get a vertical scrollbar wired via -yscrollcommand/-command") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.scrollable(:region) { |s| s.list(:items) }
      end
      session.run_async
      session.app.update

      region_path = session[:region].path
      list_path = session[:items].path
      vsb_path = "#{region_path}.vsb"
      hsb_path = "#{region_path}.hsb"

      assert_equal '1', session.app.tcl_eval("winfo exists #{vsb_path}")
      assert_equal '0', session.app.tcl_eval("winfo exists #{hsb_path}"), "y: defaults to true, x: to false"
      assert_equal "#{vsb_path} set", session.app.command(list_path, :cget, '-yscrollcommand')
      assert_equal "#{list_path} yview", session.app.command(vsb_path, :cget, '-command')

      session.app.destroy
    end
  end

  def test_x_true_also_wires_a_horizontal_scrollbar
    assert_tk_app("x: true should additionally wire a horizontal scrollbar") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.scrollable(:region, x: true) { |s| s.list(:items) }
      end
      session.run_async
      session.app.update

      region_path = session[:region].path
      list_path = session[:items].path
      hsb_path = "#{region_path}.hsb"

      assert_equal '1', session.app.tcl_eval("winfo exists #{hsb_path}")
      assert_equal "#{hsb_path} set", session.app.command(list_path, :cget, '-xscrollcommand')
      assert_equal "#{list_path} xview", session.app.command(hsb_path, :cget, '-command')

      session.app.destroy
    end
  end

  def test_y_false_omits_the_vertical_scrollbar
    assert_tk_app("y: false should leave a scrollable with no scrollbar at all if x: isn't given either") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.scrollable(:region, y: false) { |s| s.list(:items) }
      end
      session.run_async
      session.app.update

      region_path = session[:region].path
      assert_equal '0', session.app.tcl_eval("winfo exists #{region_path}.vsb")
      assert_equal '0', session.app.tcl_eval("winfo exists #{region_path}.hsb")

      session.app.destroy
    end
  end

  def test_text_area_and_canvas_are_also_treated_as_native
    assert_tk_app("text_area and canvas children should get the same direct scrollbar wiring as list") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.scrollable(:notes) { |s| s.text_area(:body) }
        ui.scrollable(:board) { |s| s.canvas(:draw) }
      end
      session.run_async
      session.app.update

      notes_vsb = "#{session[:notes].path}.vsb"
      board_vsb = "#{session[:board].path}.vsb"
      assert_equal "#{notes_vsb} set", session.app.command(session[:body].path, :cget, '-yscrollcommand')
      assert_equal "#{board_vsb} set", session.app.command(session[:draw].path, :cget, '-yscrollcommand')

      session.app.destroy
    end
  end

  def test_frame_case_wraps_arbitrary_content_in_a_canvas_and_viewport
    assert_tk_app("a scrollable panel of arbitrary widgets should be wrapped in a canvas + embedded frame") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.scrollable(:region) do |s|
          s.column(:rows) { |c| 30.times { |i| c.button(text: "Row #{i}") } }
        end
      end
      session.run_async
      session.app.update
      session.app.update_idletasks

      region_path = session[:region].path
      canvas_path = "#{region_path}.canvas"
      viewport_path = "#{canvas_path}.viewport"
      rows_path = session[:rows].path

      assert_equal '1', session.app.tcl_eval("winfo exists #{canvas_path}")
      assert_equal '1', session.app.tcl_eval("winfo exists #{viewport_path}")
      assert_equal viewport_path, rows_path.sub(/\.\w+\z/, ''), "the column should live inside the viewport, not directly under the scrollable"
      assert_equal '1', session.app.tcl_eval("winfo exists #{region_path}.vsb")
      assert_equal "#{region_path}.vsb set", session.app.command(canvas_path, :cget, '-yscrollcommand')

      scrollregion = session.app.tcl_eval("#{canvas_path} cget -scrollregion")
      refute_empty scrollregion, "the scrollregion should track the viewport's content size"
      height = scrollregion.split.last.to_i
      assert_operator height, :>, 200, "30 stacked buttons should produce a tall scrollregion"

      session.app.destroy
    end
  end

  def test_frame_case_syncs_the_viewport_width_to_the_canvas_by_default
    assert_tk_app("without x: scrolling, resizing the canvas should resize the embedded viewport to match") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.window(:win, geometry: '400x300') do |w|
          w.scrollable(:region) { |s| s.column(:rows) { |c| c.button(text: 'Row') } }
        end
      end
      session.run_async
      session[:win].show
      session.app.update
      session.app.update_idletasks

      canvas_path = "#{session[:region].path}.canvas"
      viewport_path = "#{canvas_path}.viewport"

      canvas_width = session.app.tcl_eval("winfo width #{canvas_path}")
      viewport_width = session.app.tcl_eval("winfo width #{viewport_path}")
      assert_equal canvas_width, viewport_width

      session.app.destroy
    end
  end

  def test_frame_case_with_x_true_does_not_force_the_viewport_width_to_match_the_canvas
    assert_tk_app("x: true should leave the viewport free to be wider than the canvas, for horizontal scrolling") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.scrollable(:region, x: true) { |s| s.column(:rows) { |c| c.button(text: 'Row') } }
      end
      session.run_async
      session.app.update

      canvas_path = "#{session[:region].path}.canvas"
      assert_equal '', session.app.tcl_eval("bind #{canvas_path} <Configure>"),
        "no width-sync binding should be wired when x: true"

      session.app.destroy
    end
  end

  def test_scrollable_participates_in_normal_layout_like_any_other_container
    assert_tk_app("a scrollable nested in a column with grow: true should realize and map without error") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.column do |c|
          c.label(text: 'Header')
          c.scrollable(:region, grow: true) { |s| s.list(:items) }
        end
      end
      session.run_async
      session.app.update

      assert session.app.winfo.ismapped?(session[:region].path)

      session.app.destroy
    end
  end

  def test_no_widget_in_the_scrollable_subtree_has_conflicting_geometry_managers
    assert_tk_app("grid (region) and pack (viewport content) must never collide on the same master") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.scrollable(:native_region) { |s| s.list(:items) }
        ui.scrollable(:frame_region) { |s| s.column { |c| c.button(text: 'A') } }
      end
      session.run_async
      session.app.update

      check = lambda do |path|
        children = session.app.split_list(session.app.tcl_eval("winfo children #{path}"))
        managers = children.map { |child| session.app.tcl_eval("winfo manager #{child}") }.reject(&:empty?).uniq
        assert_operator managers.length, :<=, 1,
          "#{path} has children managed by more than one geometry manager: #{managers.inspect}"
        children.each { |child| check.call(child) }
      end
      check.call('.')

      session.app.destroy
    end
  end
end
