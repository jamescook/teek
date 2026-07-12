# frozen_string_literal: true

# Tests for text-tag callback cleanup - a text widget's tags aren't windows,
# so a tag's bound callback never fires <Destroy> on its own; the widget
# that owns it is typically long-lived and reused (log panes, editors), so
# tags churn while the widget persists. Tracking reconciles against Tk's
# live tag state (tag names + tag bind readback) after every mutating call,
# the same full-scan style Teek::Menu already uses - text tags have no
# menu-style renumbering risk (tag name is a stable hash key), so this is
# actually simpler than menu, not harder.
#
# Interp#callback_ids is a plain reader on the interpreter's callback
# table - see also test_bind.rb, test_menu.rb.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestTextTags < Minitest::Test
  include TeekTestHelper

  def test_tag_bind_fires_when_insert_cursor_is_within_the_tagged_range
    assert_tk_app("tag_bind should fire when the insert cursor is within the tagged range") do
      app.show
      txt = app.create_widget(:text)
      txt.pack
      txt.command(:insert, '1.0', 'hello world')
      txt.command('tag', 'add', 'greeting', '1.0', '1.5')

      fired = false
      txt.tag_bind('greeting', 'Key-a') { fired = true }

      txt.command('mark', 'set', 'insert', '1.2')
      app.tcl_eval("focus -force #{txt.path}")
      app.update
      app.tcl_eval("event generate #{txt.path} <Key-a>")
      app.update

      assert fired, "tag binding did not fire"
    end
  end

  def test_tag_bind_rebind_does_not_leak_callbacks
    assert_tk_app("rebinding the same tag+event should not grow callback count") do
      txt = app.create_widget(:text)

      txt.tag_bind('mytag', 'Button-1') { }
      baseline = app.interp.callback_ids.length

      5.times { txt.tag_bind('mytag', 'Button-1') { } }

      assert_equal baseline, app.interp.callback_ids.length,
        "rebinding should replace, not accumulate, the registered callback"
    end
  end

  def test_tag_unbind_releases_callback
    assert_tk_app("tag_unbind should release the registered callback") do
      txt = app.create_widget(:text)
      baseline = app.interp.callback_ids.length

      txt.tag_bind('mytag', 'Button-1') { }
      assert_equal baseline + 1, app.interp.callback_ids.length, "tag_bind should register one callback"

      txt.tag_unbind('mytag', 'Button-1')

      assert_equal baseline, app.interp.callback_ids.length, "tag_unbind should release the callback"
    end
  end

  def test_tag_delete_releases_callbacks
    assert_tk_app("tag_delete should release all of that tag's bound callbacks") do
      txt = app.create_widget(:text)
      baseline = app.interp.callback_ids.length

      txt.tag_bind('mytag', 'Button-1') { }
      txt.tag_bind('mytag', 'Key-a') { }
      assert_equal baseline + 2, app.interp.callback_ids.length, "tag_bind should register two callbacks"

      txt.tag_delete('mytag')

      assert_equal baseline, app.interp.callback_ids.length,
        "tag_delete should release all of the deleted tag's callbacks"
    end
  end

  def test_tag_delete_does_not_affect_other_tags
    assert_tk_app("deleting one tag should not release another tag's callback") do
      txt = app.create_widget(:text)
      baseline = app.interp.callback_ids.length

      txt.tag_bind('tag_a', 'Button-1') { }
      txt.tag_bind('tag_b', 'Button-1') { }
      assert_equal baseline + 2, app.interp.callback_ids.length

      txt.tag_delete('tag_a')

      assert_equal baseline + 1, app.interp.callback_ids.length,
        "only tag_a's callback should be released"
    end
  end

  def test_destroy_releases_all_tracked_tag_callbacks
    assert_tk_app("destroying a text widget should release all tracked tag callbacks") do
      txt = app.create_widget(:text)
      baseline = app.interp.callback_ids.length

      txt.tag_bind('mytag', 'Button-1') { }
      txt.tag_bind('othertag', 'Key-a') { }
      assert_equal baseline + 2, app.interp.callback_ids.length

      txt.destroy

      assert_equal baseline, app.interp.callback_ids.length,
        "destroy should release all tracked tag callbacks"
    end
  end

  def test_raw_command_tag_bind_warns_once_per_path
    assert_tk_app("building a tag binding via raw command() should warn once per path, pointing at tag_bind") do
      txt = app.create_widget(:text)

      _, err1 = capture_io do
        app.command(txt.path, 'tag', 'bind', 'rawtag', '<Button-1>', proc { })
      end
      assert_match(/tag_bind/, err1, "first raw tag bind should warn and point at #tag_bind")

      _, err2 = capture_io do
        app.command(txt.path, 'tag', 'bind', 'rawtag2', '<Button-1>', proc { })
      end
      assert_empty err2, "second raw tag bind on the same path should not warn again"
    end
  end
end
