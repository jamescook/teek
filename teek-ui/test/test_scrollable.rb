# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# ui.scrollable wraps arbitrary content in a scrolled frame - a canvas +
# embedded viewport, since arbitrary widgets have no Tk scrolling protocol
# of their own to hook a scrollbar into. A bare list/text_area/table/
# tree/canvas auto-attaches a scrollbar wherever it's declared instead,
# with no ui.scrollable wrapper needed - see test_native_scrollable.rb.
# See Realizer#create_scrollable.
class TestScrollable < Minitest::Test
  include TeekTestHelper

  def test_wraps_content_in_a_canvas_and_embedded_viewport
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

      scrollregion = session.app.tcl_eval("#{canvas_path} cget -scrollregion")
      refute_empty scrollregion, "the scrollregion should track the viewport's content size"
      height = scrollregion.split.last.to_i
      assert_operator height, :>, 200, "30 stacked buttons should produce a tall scrollregion"

      session.app.destroy
    end
  end

  def test_y_defaults_to_true_and_x_to_false
    assert_tk_app("a scrollable should default to a vertical scrollbar only") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.scrollable(:region) { |s| s.column { |c| c.button(text: 'Row') } }
      end
      session.run_async
      session.app.update

      region_path = session[:region].path
      assert_equal '1', session.app.tcl_eval("winfo exists #{region_path}.vsb")
      assert_equal '0', session.app.tcl_eval("winfo exists #{region_path}.hsb")

      session.app.destroy
    end
  end

  def test_y_false_omits_the_vertical_scrollbar
    assert_tk_app("y: false should leave no scrollbar at all if x: isn't given either") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.scrollable(:region, y: false) { |s| s.column { |c| c.button(text: 'Row') } }
      end
      session.run_async
      session.app.update

      region_path = session[:region].path
      assert_equal '0', session.app.tcl_eval("winfo exists #{region_path}.vsb")
      assert_equal '0', session.app.tcl_eval("winfo exists #{region_path}.hsb")

      session.app.destroy
    end
  end

  def test_x_true_also_wires_a_horizontal_scrollbar
    assert_tk_app("x: true should additionally wire a horizontal scrollbar") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.scrollable(:region, x: true) { |s| s.column { |c| c.button(text: 'Row') } }
      end
      session.run_async
      session.app.update

      region_path = session[:region].path
      assert_equal '1', session.app.tcl_eval("winfo exists #{region_path}.hsb")

      session.app.destroy
    end
  end

  def test_syncs_the_viewport_width_to_the_canvas_by_default
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

  def test_with_x_true_does_not_force_the_viewport_width_to_match_the_canvas
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

  def test_participates_in_normal_layout_like_any_other_container
    assert_tk_app("a scrollable nested in a column with grow: true should realize and map without error") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.column do |c|
          c.label(text: 'Header')
          c.scrollable(:region, grow: true) { |s| s.checkbox(text: 'A checkbox') }
        end
      end
      session.run_async
      session.app.update

      assert session.app.winfo.ismapped?(session[:region].path)

      session.app.destroy
    end
  end

  def test_no_widget_in_the_subtree_has_conflicting_geometry_managers
    assert_tk_app("grid (region) and pack (viewport content) must never collide on the same master") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Scrollable Test') do |ui|
        ui.scrollable(:region_a) { |s| s.column { |c| c.button(text: 'A') } }
        ui.scrollable(:region_b, x: true) { |s| s.row { |r| r.button(text: 'B') } }
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
