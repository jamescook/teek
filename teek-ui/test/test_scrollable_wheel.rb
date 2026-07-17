# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# create_scrollable wires the scrollbar and scrollregion sync (see
# test_scrollable.rb), but the frame case's canvas + embedded viewport has
# no wheel handling of its own - a bare canvas doesn't respond to
# <MouseWheel>, and neither do arbitrary widgets nested inside it. These
# confirm the fix: a shared bindtag (see Realizer#wire_wheel_scroll)
# applied to the canvas, the viewport, and everything already inside it,
# so wheeling over any of them scrolls the same region - and that a
# widget with no such tag is left alone.
#
# yview/xview reading is inlined as a local lambda in every block (not a
# helper method) - assert_tk_app re-evaluates each block's own source text
# in a separate worker process, which has no access to methods defined on
# this class.
class TestScrollableWheel < Minitest::Test
  include TeekTestHelper

  tk_test "MouseWheel over the canvas itself should scroll it" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Scrollable Wheel Test') do |ui|
      ui.scrollable(:region) { |s| s.column { |c| 30.times { |i| c.button(text: "Row #{i}") } } }
    end
    session.run_async
    session.app.update
    session.app.update_idletasks

    canvas_path = "#{session[:region].path}.canvas"
    yview_first = -> { session.app.tcl_eval("#{canvas_path} yview").split.first.to_f }
    assert_equal 0.0, yview_first.call

    session.app.tcl_eval("event generate #{canvas_path} <MouseWheel> -delta -120")
    session.app.update

    assert_operator yview_first.call, :>, 0.0
  end

  tk_test "MouseWheel over a widget nested deep inside the viewport should still scroll the canvas" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Scrollable Wheel Test') do |ui|
      ui.scrollable(:region) do |s|
        s.column { |c| 30.times { |i| c.button("row_#{i}".to_sym, text: "Row #{i}") } }
      end
    end
    session.run_async
    session.app.update
    session.app.update_idletasks

    canvas_path = "#{session[:region].path}.canvas"
    nested_button_path = session[:row_5].path
    yview_first = -> { session.app.tcl_eval("#{canvas_path} yview").split.first.to_f }

    session.app.tcl_eval("event generate #{nested_button_path} <MouseWheel> -delta -120")
    session.app.update

    assert_operator yview_first.call, :>, 0.0
  end

  tk_test "MouseWheel over a widget with no bindtag from the scrollable region should leave it alone" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Scrollable Wheel Test') do |ui|
      ui.scrollable(:region) { |s| s.column { |c| 30.times { |i| c.button(text: "Row #{i}") } } }
      ui.button(:elsewhere, text: 'Elsewhere')
    end
    session.run_async
    session.app.update
    session.app.update_idletasks

    canvas_path = "#{session[:region].path}.canvas"
    yview_first = -> { session.app.tcl_eval("#{canvas_path} yview").split.first.to_f }

    session.app.tcl_eval("event generate #{session[:elsewhere].path} <MouseWheel> -delta -120")
    session.app.update

    assert_equal 0.0, yview_first.call
  end

  tk_test "the X11 Button-4/Button-5 wheel fallback should scroll the region too" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Scrollable Wheel Test') do |ui|
      ui.scrollable(:region) { |s| s.column { |c| 30.times { |i| c.button(text: "Row #{i}") } } }
    end
    session.run_async
    session.app.update
    session.app.update_idletasks

    canvas_path = "#{session[:region].path}.canvas"
    yview_first = -> { session.app.tcl_eval("#{canvas_path} yview").split.first.to_f }

    session.app.tcl_eval("event generate #{canvas_path} <Button-5>")
    session.app.update
    after_down = yview_first.call
    assert_operator after_down, :>, 0.0

    session.app.tcl_eval("event generate #{canvas_path} <Button-4>")
    session.app.update
    assert_operator yview_first.call, :<, after_down
  end

  tk_test "Shift-MouseWheel should drive xview when x: true" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Scrollable Wheel Test') do |ui|
      ui.scrollable(:region, x: true) { |s| s.row { |r| 30.times { |i| r.button(text: "Col #{i}") } } }
    end
    session.run_async
    session.app.update
    session.app.update_idletasks

    canvas_path = "#{session[:region].path}.canvas"
    xview_first = -> { session.app.tcl_eval("#{canvas_path} xview").split.first.to_f }
    assert_equal 0.0, xview_first.call

    session.app.tcl_eval("event generate #{canvas_path} <Shift-MouseWheel> -delta -120")
    session.app.update

    assert_operator xview_first.call, :>, 0.0
  end

  tk_test "MouseWheel over a native scrollable widget (Tk's own class binding) should work through the DSL" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Scrollable Wheel Test') do |ui|
      ui.scrollable(:region) { |s| s.list(:items, height: 5) }
    end
    session.run_async
    session.app.update

    list_path = session[:items].path
    session.app.command(list_path, :insert, :end, *(1..60).map { |i| "Item #{i}" })
    session.app.update_idletasks

    yview_first = -> { session.app.tcl_eval("#{list_path} yview").split.first.to_f }
    assert_equal 0.0, yview_first.call

    session.app.tcl_eval("event generate #{list_path} <MouseWheel> -delta -120")
    session.app.update

    assert_operator yview_first.call, :>, 0.0
  end
end
