# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

class TestEvents < Minitest::Test
  include TeekTestHelper

  tk_test "on_click should fire when Button-1 is generated on the widget" do
    require 'teek/ui'

    clicked = false
    session = Teek::UI.app(title: 'Events Test') { |ui| ui.button(:go, text: 'Go') }
    session.run_async
    session.app.update
    session[:go].on_click { clicked = true }

    session.app.tcl_eval("event generate #{session[:go].path} <Button-1>")
    session.app.update

    assert clicked, "on_click did not fire"
  end

  tk_test "on_right_click should fire on Button-3 (Linux/Windows right-click)" do
    require 'teek/ui'

    clicked = false
    session = Teek::UI.app(title: 'Events Test') { |ui| ui.button(:go, text: 'Go') }
    session.run_async
    session.app.update
    session[:go].on_right_click { clicked = true }

    session.app.tcl_eval("event generate #{session[:go].path} <Button-3>")
    session.app.update

    assert clicked, "on_right_click did not fire on Button-3"
  end

  tk_test "on_drag should deliver Integer x/y, not raw Tcl strings" do
    require 'teek/ui'

    received = nil
    session = Teek::UI.app(title: 'Events Test') { |ui| ui.panel(:area, width: 200, height: 200) }
    session.run_async
    session.app.update
    session[:area].on_drag { |x, y| received = [x, y] }

    session.app.tcl_eval("event generate #{session[:area].path} <B1-Motion> -x 40 -y 55")
    session.app.update

    assert_equal [40, 55], received
    assert_kind_of Integer, received[0]
    assert_kind_of Integer, received[1]
  end

  tk_test "on_drag should convert raw window coords through canvasx/canvasy when bound to a canvas" do
    require 'teek/ui'

    received = nil
    session = Teek::UI.app(title: 'Events Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    board_path = session[:board].path
    # scroll the canvas so canvasx/canvasy meaningfully differ from raw %x/%y -
    # otherwise a bug that skips conversion entirely could still pass by luck.
    session.app.tcl_eval("#{board_path} configure -scrollregion {0 0 1000 1000}")
    session.app.tcl_eval("#{board_path} xview moveto 0.5")
    session.app.update

    session[:board].on_drag { |x, y| received = [x, y] }
    session.app.tcl_eval("event generate #{board_path} <B1-Motion> -x 50 -y 60")
    session.app.update

    expected_x = session.app.command(board_path, :canvasx, 50).to_f.round
    expected_y = session.app.command(board_path, :canvasy, 60).to_f.round

    refute_nil received
    assert_equal [expected_x, expected_y], received
    refute_equal [50, 60], received, "the canvas is scrolled, so conversion should actually change the coordinates"
  end

  tk_test "on_key(:enter) should fire on a real Return keypress" do
    require 'teek/ui'

    fired = false
    session = Teek::UI.app(title: 'Events Test') { |ui| ui.text_box(:query) }
    session.run_async
    session.app.update
    session[:query].on_key(:enter) { fired = true }

    path = session[:query].path
    session.app.tcl_eval("focus -force #{path}")
    session.app.update
    session.app.tcl_eval("event generate #{path} <Return>")
    session.app.update

    assert fired, "on_key(:enter) did not fire"
  end

  tk_test "on_key('Ctrl-s') should fire on a real Control-s keypress" do
    require 'teek/ui'

    fired = false
    session = Teek::UI.app(title: 'Events Test') { |ui| ui.text_box(:query) }
    session.run_async
    session.app.update
    session[:query].on_key('Ctrl-s') { fired = true }

    path = session[:query].path
    session.app.tcl_eval("focus -force #{path}")
    session.app.update
    session.app.tcl_eval("event generate #{path} <Control-s>")
    session.app.update

    assert fired, "on_key('Ctrl-s') did not fire"
  end

  tk_test "on_key('Shift-Tab') should fire even though X11 delivers it as ISO_Left_Tab, not Shift-Tab" do
    require 'teek/ui'

    fired = false
    session = Teek::UI.app(title: 'Events Test') { |ui| ui.text_box(:query) }
    session.run_async
    session.app.update
    session[:query].on_key('Shift-Tab') { fired = true }

    path = session[:query].path
    session.app.tcl_eval("focus -force #{path}")
    session.app.update
    session.app.tcl_eval("event generate #{path} <ISO_Left_Tab>")
    session.app.update

    assert fired, "on_key('Shift-Tab') did not fire for the X11 ISO_Left_Tab keysym"
  end
end
