# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# ui.overlay floats a single widget on top of the enclosing ui.canvas at a
# fixed corner/edge/center anchor, via Tk's `place` geometry manager - the
# one legitimate "absolute position" case (a status readout or button bar
# layered over canvas content), not a general-purpose layout mode.
class TestOverlay < Minitest::Test
  include TeekTestHelper

  tk_test "overlay should place its widget in the canvas at the anchor's relx/rely/anchor" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Overlay Test') do |ui|
      ui.canvas(:board, width: 300, height: 200) do |cv|
        cv.overlay(at: :bottom_right) { ui.label(:status, text: 'Ready') }
      end
    end
    session.run_async
    session.app.update

    info = session.app.tcl_eval("place info #{session[:status].path}")
    assert_match(/-in #{Regexp.escape(session[:board].path)}(?:\s|$)/, info)
    assert_match(/-relx 1(?:\s|$)/, info)
    assert_match(/-rely 1(?:\s|$)/, info)
    assert_match(/-anchor se(?:\s|$)/, info)

    session.app.destroy
  end

  tk_test "two overlays on the same canvas should each land at their own anchor" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Overlay Test') do |ui|
      ui.canvas(:board, width: 300, height: 200) do |cv|
        cv.overlay(at: :top_left) { ui.label(:status, text: 'Ready') }
        cv.overlay(at: :top_right) { ui.row(:controls) { ui.button(:pause, text: 'Pause') } }
      end
    end
    session.run_async
    session.app.update

    status_info = session.app.tcl_eval("place info #{session[:status].path}")
    controls_info = session.app.tcl_eval("place info #{session[:controls].path}")

    assert_match(/-relx 0(?:\s|$)/, status_info)
    assert_match(/-rely 0(?:\s|$)/, status_info)
    assert_match(/-anchor nw(?:\s|$)/, status_info)

    assert_match(/-relx 1(?:\s|$)/, controls_info)
    assert_match(/-rely 0(?:\s|$)/, controls_info)
    assert_match(/-anchor ne(?:\s|$)/, controls_info)

    session.app.destroy
  end

  tk_test "an overlay's real on-screen position should scale with the canvas, not stay fixed" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Overlay Test') do |ui|
      ui.canvas(:board, width: 200, height: 200) do |cv|
        cv.overlay(at: :bottom_right) { ui.label(:status, text: 'Ready') }
      end
    end
    session.run_async
    session.app.update

    before_x = session.app.tcl_eval("winfo x #{session[:status].path}").to_i
    before_y = session.app.tcl_eval("winfo y #{session[:status].path}").to_i

    session.app.tcl_eval("#{session[:board].path} configure -width 500 -height 500")
    session.app.update

    after_x = session.app.tcl_eval("winfo x #{session[:status].path}").to_i
    after_y = session.app.tcl_eval("winfo y #{session[:status].path}").to_i

    assert_operator after_x, :>, before_x, "the overlay should have followed the canvas's new bottom-right corner"
    assert_operator after_y, :>, before_y, "the overlay should have followed the canvas's new bottom-right corner"

    session.app.destroy
  end

  tk_test "overlay declared outside ui.canvas should raise immediately, not silently do nothing" do
    require 'teek/ui'

    error = assert_raises(ArgumentError) do
      Teek::UI.app(title: 'Overlay Test') { |ui| ui.overlay(at: :top_left) { ui.label(text: 'oops') } }
    end
    assert_match(/ui\.canvas/i, error.message)
  end

  tk_test "overlay given an unrecognized at: should raise, not silently no-op" do
    require 'teek/ui'

    error = assert_raises(ArgumentError) do
      Teek::UI.app(title: 'Overlay Test') do |ui|
        ui.canvas(:board, width: 200, height: 200) { |cv| cv.overlay(at: :middle) { ui.label(text: 'oops') } }
      end
    end
    assert_match(/at:/, error.message)
  end

  tk_test "overlay's block must build exactly one widget" do
    require 'teek/ui'

    empty_error = assert_raises(ArgumentError) do
      Teek::UI.app(title: 'Overlay Test') do |ui|
        ui.canvas(:board, width: 200, height: 200) { |cv| cv.overlay(at: :top_left) { } }
      end
    end
    assert_match(/exactly one/i, empty_error.message)

    many_error = assert_raises(ArgumentError) do
      Teek::UI.app(title: 'Overlay Test') do |ui|
        ui.canvas(:board, width: 200, height: 200) do |cv|
          cv.overlay(at: :top_left) do
            ui.label(text: 'one')
            ui.label(text: 'two')
          end
        end
      end
    end
    assert_match(/exactly one/i, many_error.message)
  end
end
