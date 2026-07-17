# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'
require 'teek/ui/canvas_item'

# ui.canvas gains a real item-drawing vocabulary (Handle#line/oval/polygon/
# rectangle/text/arc/bitmap, each returning a CanvasItem) instead of being a
# bare container only reachable via ui.raw + raw app.command(:create, ...).
# CanvasItem addresses Tk's own tagOrId uniformly, so a shared `tags:` group
# is movable/configurable/deletable exactly like a single item - see
# test_tagged_addresses_every_item_sharing_a_tag_as_one_group below.
class TestCanvasItems < Minitest::Test
  include TeekTestHelper

  def test_virtual_path_marks_past_the_real_tk_path
    item = Teek::UI::CanvasItem.new(:fake_app, '.board', 'I3')

    assert_equal '.board!I3', item.virtual_path
  end

  tk_test "ui.canvas#line should create a real line item" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    item = session[:board].line(10, 10, 50, 50, fill: 'red')

    assert_equal 'line', session.app.tcl_eval("#{session[:board].path} type #{item.tag_or_id}")
    assert_equal [10.0, 10.0, 50.0, 50.0], item.coords
  end

  tk_test "every shape method should create the matching Tk item type" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    board = session[:board]
    items = {
      'oval' => board.oval(10, 10, 40, 40),
      'rectangle' => board.rectangle(10, 10, 40, 40),
      'polygon' => board.polygon(10, 10, 40, 10, 25, 40),
      'text' => board.text(10, 10, text: 'Hi'),
      'arc' => board.arc(10, 10, 40, 40, start: 0, extent: 90),
      'bitmap' => board.bitmap(10, 10, bitmap: 'gray25'),
    }

    items.each do |expected_type, item|
      assert_equal expected_type, session.app.tcl_eval("#{board.path} type #{item.tag_or_id}")
    end
  end

  tk_test "flat and nested coordinate arguments should produce the same item" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    flat = session[:board].line(10, 10, 50, 50)
    nested = session[:board].line([10, 10], [50, 50])

    assert_equal flat.coords, nested.coords
  end

  tk_test "move should shift by a relative delta" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    item = session[:board].oval(10, 10, 30, 30)
    item.move(5, -3)

    assert_equal [15.0, 7.0, 35.0, 27.0], item.coords
  end

  tk_test "coords= should replace the coordinate list, not shift it" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    item = session[:board].line(0, 0, 10, 10)
    item.coords = [1, 2, 3, 4, 5, 6]

    assert_equal [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], item.coords
  end

  tk_test "configure should mutate item options" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    item = session[:board].rectangle(10, 10, 40, 40, fill: 'blue')
    item.configure(fill: 'green', width: 3)

    assert_equal 'green', item[:fill]
    assert_equal '3.0', item[:width]
  end

  tk_test "item[:opt] should read, item[:opt] = value should write" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    item = session[:board].oval(10, 10, 40, 40, fill: 'red')
    assert_equal 'red', item[:fill]

    item[:fill] = 'purple'
    assert_equal 'purple', item[:fill]
  end

  tk_test "delete should remove the item from the canvas" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    item = session[:board].oval(10, 10, 40, 40)
    assert item.exists?

    item.delete

    refute item.exists?
    assert_nil item.bounds
  end

  tk_test "bring_to_front/send_to_back with no target should move all the way" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    board = session[:board]
    a = board.oval(10, 10, 20, 20)
    b = board.oval(10, 10, 20, 20)
    c = board.oval(10, 10, 20, 20)
    stacking = -> { session.app.split_list(session.app.tcl_eval("#{board.path} find all")) }

    assert_equal [a.tag_or_id, b.tag_or_id, c.tag_or_id], stacking.call

    a.bring_to_front
    assert_equal [b.tag_or_id, c.tag_or_id, a.tag_or_id], stacking.call

    c.send_to_back
    assert_equal [c.tag_or_id, b.tag_or_id, a.tag_or_id], stacking.call
  end

  tk_test "bring_to_front(target) should reposition just above target, not to the very top" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    board = session[:board]
    a = board.oval(10, 10, 20, 20)
    b = board.oval(10, 10, 20, 20)
    c = board.oval(10, 10, 20, 20)
    stacking = -> { session.app.split_list(session.app.tcl_eval("#{board.path} find all")) }

    a.bring_to_front(b)
    assert_equal [b.tag_or_id, a.tag_or_id, c.tag_or_id], stacking.call
  end

  tk_test "scale should resize relative to the given origin" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    item = session[:board].rectangle(10, 10, 20, 20)
    item.scale(10, 10, 2, 2)

    assert_equal [10.0, 10.0, 30.0, 30.0], item.coords
  end

  tk_test "bounds should return the item's bounding box" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    item = session[:board].rectangle(10, 10, 40, 40, outline: '', fill: 'red')
    box = item.bounds

    refute_nil box
    assert_equal 4, box.length
  end

  tk_test "tagged should address a shared tag as a single movable/configurable/deletable group" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    board = session[:board]
    one = board.oval(10, 10, 20, 20, tags: 'group_a')
    two = board.oval(30, 30, 40, 40, tags: 'group_a')
    board.oval(50, 50, 60, 60, tags: 'group_b')

    group = board.tagged('group_a')
    assert group.exists?

    group.move(5, 5)
    assert_equal [15.0, 15.0, 25.0, 25.0], one.coords
    assert_equal [35.0, 35.0, 45.0, 45.0], two.coords

    group.configure(fill: 'orange')
    assert_equal 'orange', one[:fill]
    assert_equal 'orange', two[:fill]

    group.delete
    refute one.exists?
    refute two.exists?
    assert board.tagged('group_b').exists?
  end

  tk_test "tagged on an unused tag should report exists? false, not raise" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    refute session[:board].tagged('nothing_has_this_tag').exists?
  end

  # Item-level canvas bindings only fire through Tk's "current item"
  # tracking, which real event generate positioning depends on real X11
  # pointer state - unreliable under Xvfb (see teek core's own
  # test_canvas_bindings.rb). Tk has no "invoke this item binding"
  # command either way, so these read back the bound script and eval it
  # directly - the same pattern teek core already uses to verify item
  # binding dispatch without needing a real synthetic click to land.

  tk_test "on_click's bound script should be scoped per-item, not shared" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    board = session[:board]
    a = board.oval(10, 10, 30, 30)
    b = board.oval(100, 100, 120, 120)

    a_hits = 0
    b_hits = 0
    a.on_click { a_hits += 1 }
    b.on_click { b_hits += 1 }

    a_script = session.app.tcl_eval("#{board.path} bind #{a.tag_or_id} <Button-1>")
    session.app.tcl_eval(a_script)
    assert_equal 1, a_hits, "invoking A's own binding should fire A's handler"
    assert_equal 0, b_hits, "invoking A's own binding should not fire B's handler"

    b_script = session.app.tcl_eval("#{board.path} bind #{b.tag_or_id} <Button-1>")
    session.app.tcl_eval(b_script)
    assert_equal 1, a_hits, "invoking B's own binding should not fire A's handler again"
    assert_equal 1, b_hits, "invoking B's own binding should fire B's handler"
  end

  tk_test "on_right_click should bind a script that fires the given block" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    board = session[:board]
    item = board.oval(10, 10, 30, 30)
    fired = false
    item.on_right_click { fired = true }

    script = session.app.tcl_eval("#{board.path} bind #{item.tag_or_id} <Button-3>")
    session.app.tcl_eval(script)

    assert fired, "on_right_click's bound script did not fire the given block"
  end

  tk_test "on_right_click(menu) should tk_popup the given menu at the click's root coordinates" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') do |ui|
      ui.context_menu(:ctx) { |m| m.item(label: 'Delete') { } }
      ui.canvas(:board, width: 200, height: 200)
    end
    session.run_async
    session.app.update

    board = session[:board]
    item = board.oval(10, 10, 30, 30)
    item.on_right_click(session[:ctx])

    session.app.tcl_eval(<<~TCL)
      proc tk_popup {args} {
        set ::last_popup_call $args
      }
    TCL

    # %X/%Y are literal %-substitution codes Tk fills in at real dispatch
    # time - substitute them ourselves to simulate a click at (123, 456)
    # root coordinates without needing a real synthetic click to land.
    script = session.app.tcl_eval("#{board.path} bind #{item.tag_or_id} <Button-3>")
    session.app.tcl_eval(script.sub('%X', '123').sub('%Y', '456'))

    captured = session.app.split_list(session.app.tcl_eval('set ::last_popup_call'))
    assert_equal [session[:ctx].path, '123', '456'], captured
  end

  tk_test "on_right_click with neither a menu nor a block should raise" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    item = session[:board].oval(10, 10, 30, 30)
    assert_raises(ArgumentError) { item.on_right_click }
  end

  tk_test "on_right_click with both a menu and a block should raise" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') do |ui|
      ui.context_menu(:ctx) { |m| m.item(label: 'Delete') { } }
      ui.canvas(:board, width: 200, height: 200)
    end
    session.run_async
    session.app.update

    item = session[:board].oval(10, 10, 30, 30)
    error = assert_raises(ArgumentError) { item.on_right_click(session[:ctx]) { } }
    assert_match(/menu/i, error.message)
  end

  tk_test "on_right_click given a non-menu handle should raise a clear error" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    item = session[:board].oval(10, 10, 30, 30)
    error = assert_raises(ArgumentError) { item.on_right_click(session[:board]) }
    assert_match(/menu/i, error.message)
  end

  tk_test "on_drag should deliver canvasx/canvasy-converted coordinates, not raw window coordinates" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    board_path = session[:board].path
    # scroll the canvas so canvasx/canvasy meaningfully differ from raw %x/%y -
    # otherwise a bug that skips conversion entirely could still pass by luck.
    session.app.tcl_eval("#{board_path} configure -scrollregion {0 0 1000 1000}")
    session.app.tcl_eval("#{board_path} xview moveto 0.5")
    session.app.update

    item = session[:board].rectangle(0, 0, 1000, 1000)
    received = nil
    item.on_drag { |x, y| received = [x, y] }

    # %x/%y are literal %-substitution codes Tk fills in at real dispatch
    # time - substitute them ourselves to simulate a motion at raw window
    # coordinates (50, 60) without needing a real synthetic drag to land.
    script = session.app.tcl_eval("#{board_path} bind #{item.tag_or_id} <B1-Motion>")
    session.app.tcl_eval(script.sub('%x', '50').sub('%y', '60'))

    expected_x = session.app.command(board_path, :canvasx, 50).to_f.round
    expected_y = session.app.command(board_path, :canvasy, 60).to_f.round

    refute_nil received
    assert_equal [expected_x, expected_y], received
    refute_equal [50, 60], received, "the canvas is scrolled, so conversion should actually change the coordinates"
  end

  tk_test "draggable should move the item by the drag delta, with no coordinate math in app code" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    board = session[:board]
    item = board.oval(10, 10, 30, 30)
    item.draggable

    # Same script-readback approach as the other item-event tests above -
    # substitute %x/%y ourselves to simulate a press at (20, 20) then a
    # drag to (30, 25), a (10, 5) delta.
    press_script = session.app.tcl_eval("#{board.path} bind #{item.tag_or_id} <Button-1>")
    session.app.tcl_eval(press_script.sub('%x', '20').sub('%y', '20'))

    drag_script = session.app.tcl_eval("#{board.path} bind #{item.tag_or_id} <B1-Motion>")
    session.app.tcl_eval(drag_script.sub('%x', '30').sub('%y', '25'))

    assert_equal [20.0, 15.0, 40.0, 35.0], item.coords, "the item should have moved by the (10, 5) drag delta"
  end

  tk_test "deleting an item should release its on_click/on_drag callbacks, not leak them" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
    session.run_async
    session.app.update

    baseline = session.app.interp.callback_ids.length

    item = session[:board].oval(10, 10, 30, 30)
    item.on_click { }
    item.on_drag { |_x, _y| }
    assert_equal baseline + 2, session.app.interp.callback_ids.length,
      "on_click and on_drag should each register one callback"

    item.delete

    assert_equal baseline, session.app.interp.callback_ids.length,
      "deleting the item should release both its click and drag callbacks - on_drag's %-substitution " \
      "args must not stop the leak-tracking regex from recognizing the binding"
  end

  tk_test "shape creation and tagged should raise a clear error on a non-canvas handle" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.panel(:not_a_canvas) }
    session.run_async
    session.app.update

    error = assert_raises(ArgumentError) { session[:not_a_canvas].line(0, 0, 10, 10) }
    assert_match(/canvas/i, error.message)

    assert_raises(ArgumentError) { session[:not_a_canvas].tagged('whatever') }
  end
end
