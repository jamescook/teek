# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# ui.canvas gains a real item-drawing vocabulary (Handle#line/oval/polygon/
# rectangle/text/arc/bitmap, each returning a CanvasItem) instead of being a
# bare container only reachable via ui.raw + raw app.command(:create, ...).
# CanvasItem addresses Tk's own tagOrId uniformly, so a shared `tags:` group
# is movable/configurable/deletable exactly like a single item - see
# test_tagged_addresses_every_item_sharing_a_tag_as_one_group below.
class TestCanvasItems < Minitest::Test
  include TeekTestHelper

  def test_line_creates_a_real_item_addressable_by_the_returned_handle
    assert_tk_app("ui.canvas#line should create a real line item") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
      session.run_async
      session.app.update

      item = session[:board].line(10, 10, 50, 50, fill: 'red')

      assert_equal 'line', session.app.tcl_eval("#{session[:board].path} type #{item.tag_or_id}")
      assert_equal [10.0, 10.0, 50.0, 50.0], item.coords

      session.app.destroy
    end
  end

  def test_oval_rectangle_polygon_text_arc_bitmap_all_create_the_right_item_type
    assert_tk_app("every shape method should create the matching Tk item type") do
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

      session.app.destroy
    end
  end

  def test_coords_accepts_flat_or_nested_arguments_equivalently
    assert_tk_app("flat and nested coordinate arguments should produce the same item") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
      session.run_async
      session.app.update

      flat = session[:board].line(10, 10, 50, 50)
      nested = session[:board].line([10, 10], [50, 50])

      assert_equal flat.coords, nested.coords

      session.app.destroy
    end
  end

  def test_move_shifts_relative_to_the_current_position
    assert_tk_app("move should shift by a relative delta") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
      session.run_async
      session.app.update

      item = session[:board].oval(10, 10, 30, 30)
      item.move(5, -3)

      assert_equal [15.0, 7.0, 35.0, 27.0], item.coords

      session.app.destroy
    end
  end

  def test_coords_writer_replaces_the_coordinate_list_outright
    assert_tk_app("coords= should replace the coordinate list, not shift it") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
      session.run_async
      session.app.update

      item = session[:board].line(0, 0, 10, 10)
      item.coords = [1, 2, 3, 4, 5, 6]

      assert_equal [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], item.coords

      session.app.destroy
    end
  end

  def test_configure_mutates_multiple_options_at_once
    assert_tk_app("configure should mutate item options") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
      session.run_async
      session.app.update

      item = session[:board].rectangle(10, 10, 40, 40, fill: 'blue')
      item.configure(fill: 'green', width: 3)

      assert_equal 'green', item[:fill]
      assert_equal '3.0', item[:width]

      session.app.destroy
    end
  end

  def test_bracket_read_and_write_a_single_option
    assert_tk_app("item[:opt] should read, item[:opt] = value should write") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
      session.run_async
      session.app.update

      item = session[:board].oval(10, 10, 40, 40, fill: 'red')
      assert_equal 'red', item[:fill]

      item[:fill] = 'purple'
      assert_equal 'purple', item[:fill]

      session.app.destroy
    end
  end

  def test_delete_removes_the_item
    assert_tk_app("delete should remove the item from the canvas") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
      session.run_async
      session.app.update

      item = session[:board].oval(10, 10, 40, 40)
      assert item.exists?

      item.delete

      refute item.exists?
      assert_nil item.bounds

      session.app.destroy
    end
  end

  def test_bring_to_front_and_send_to_back_change_stacking_order
    assert_tk_app("bring_to_front/send_to_back with no target should move all the way") do
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

      session.app.destroy
    end
  end

  def test_bring_to_front_with_a_target_stacks_just_above_it
    assert_tk_app("bring_to_front(target) should reposition just above target, not to the very top") do
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

      session.app.destroy
    end
  end

  def test_scale_resizes_coordinates_relative_to_an_origin
    assert_tk_app("scale should resize relative to the given origin") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
      session.run_async
      session.app.update

      item = session[:board].rectangle(10, 10, 20, 20)
      item.scale(10, 10, 2, 2)

      assert_equal [10.0, 10.0, 30.0, 30.0], item.coords

      session.app.destroy
    end
  end

  def test_bounds_returns_the_bounding_box
    assert_tk_app("bounds should return the item's bounding box") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
      session.run_async
      session.app.update

      item = session[:board].rectangle(10, 10, 40, 40, outline: '', fill: 'red')
      box = item.bounds

      refute_nil box
      assert_equal 4, box.length

      session.app.destroy
    end
  end

  def test_tagged_addresses_every_item_sharing_a_tag_as_one_group
    assert_tk_app("tagged should address a shared tag as a single movable/configurable/deletable group") do
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

      session.app.destroy
    end
  end

  def test_tagged_on_a_tag_matching_nothing_reports_it_does_not_exist
    assert_tk_app("tagged on an unused tag should report exists? false, not raise") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.canvas(:board, width: 200, height: 200) }
      session.run_async
      session.app.update

      refute session[:board].tagged('nothing_has_this_tag').exists?

      session.app.destroy
    end
  end

  def test_shape_methods_raise_on_a_non_canvas_handle
    assert_tk_app("shape creation and tagged should raise a clear error on a non-canvas handle") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Canvas Items Test') { |ui| ui.panel(:not_a_canvas) }
      session.run_async
      session.app.update

      error = assert_raises(ArgumentError) { session[:not_a_canvas].line(0, 0, 10, 10) }
      assert_match(/canvas/i, error.message)

      assert_raises(ArgumentError) { session[:not_a_canvas].tagged('whatever') }

      session.app.destroy
    end
  end
end
