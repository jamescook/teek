# frozen_string_literal: true

# Tests for file drop support via <<DropFile>> virtual event.
# Uses event generate to simulate drops (no actual OS drag needed).

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestDrop < Minitest::Test
  include TeekTestHelper

  def test_drop_file_event_fires_callback
    assert_tk_app("<<DropFile>> should fire callback") do
      fired = false

      app.show
      app.update

      app.bind('.', '<<DropFile>>') { fired = true }

      app.tcl_eval('event generate . <<DropFile>>')
      app.update

      assert fired, "<<DropFile>> callback did not fire"
    end
  end

  def test_drop_file_event_receives_data
    assert_tk_app("<<DropFile>> should receive file path via :data") do
      received_path = nil

      app.show
      app.update

      app.bind('.', '<<DropFile>>', :data) { |path| received_path = path }

      app.tcl_eval('event generate . <<DropFile>> -data {/tmp/test.gba}')
      app.update

      assert_equal "/tmp/test.gba", received_path
    end
  end

  def test_drop_file_event_on_child_widget
    assert_tk_app("<<DropFile>> should work on child widgets") do
      received_path = nil

      app.show
      app.tcl_eval("frame .f -width 100 -height 100")
      app.tcl_eval("pack .f")
      app.update

      app.bind('.f', '<<DropFile>>', :data) { |path| received_path = path }

      app.tcl_eval('event generate .f <<DropFile>> -data {/home/user/game.gba}')
      app.update

      assert_equal "/home/user/game.gba", received_path
    end
  end

  def test_drop_file_with_spaces_in_path
    assert_tk_app("<<DropFile>> should handle paths with spaces") do
      received_path = nil

      app.show
      app.update

      app.bind('.', '<<DropFile>>', :data) { |path| received_path = path }

      app.tcl_eval('event generate . <<DropFile>> -data {/tmp/my games/rom file.gba}')
      app.update

      assert_equal "/tmp/my games/rom file.gba", received_path
    end
  end

  def test_unbind_drop_file
    assert_tk_app("unbind should remove <<DropFile>> binding") do
      count = 0

      app.show
      app.update

      app.bind('.', '<<DropFile>>') { count += 1 }

      app.tcl_eval('event generate . <<DropFile>>')
      app.update
      assert_equal 1, count

      app.unbind('.', '<<DropFile>>')

      app.tcl_eval('event generate . <<DropFile>>')
      app.update
      assert_equal 1, count, "binding still fired after unbind"
    end
  end
end
