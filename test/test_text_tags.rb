# frozen_string_literal: true

# Tests for text-tag callback tracking through plain app.command() calls -
# there's no separate wrapper method to know about. app.command recognizes
# the tag bind/delete shapes for a text (or treeview) path and tracks their
# callbacks automatically; every other Tcl interaction goes through the
# same interface.
#
# A text widget's tags aren't windows, so a tag's bound callback never
# fires <Destroy> on its own; the widget that owns it is typically
# long-lived and reused (log panes, editors), so tags churn while the
# widget persists. Tracking reconciles against Tk's live tag state (tag
# names + tag bind readback) after every mutating call, the same full-scan
# style menu tracking uses - text tags have no menu-style renumbering risk
# (tag name is a stable hash key), so this is actually simpler than menu,
# not harder.
#
# Interp#callback_ids is a plain reader on the interpreter's callback
# table - see also test_bind.rb, test_menu.rb.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestTextTags < Minitest::Test
  include TeekTestHelper

  def test_tag_bind_fires_when_insert_cursor_is_within_the_tagged_range
    assert_tk_app("a tag binding added via raw app.command should fire when the insert cursor is within the tagged range") do
      app.show
      app.command(:text, '.txt1')
      app.command(:pack, '.txt1')
      app.command('.txt1', :insert, '1.0', 'hello world')
      app.command('.txt1', 'tag', 'add', 'greeting', '1.0', '1.5')

      fired = false
      app.command('.txt1', 'tag', 'bind', 'greeting', '<Key-a>', proc { fired = true })

      app.command('.txt1', 'mark', 'set', 'insert', '1.2')
      app.tcl_eval("focus -force .txt1")
      app.update
      app.tcl_eval("event generate .txt1 <Key-a>")
      app.update

      assert fired, "tag binding did not fire"
    end
  end

  def test_tag_bind_rebind_does_not_leak_callbacks
    assert_tk_app("rebinding the same tag+event via raw app.command should not grow callback count") do
      app.command(:text, '.txt2')

      app.command('.txt2', 'tag', 'bind', 'mytag', '<Button-1>', proc { })
      baseline = app.interp.callback_ids.length

      5.times { app.command('.txt2', 'tag', 'bind', 'mytag', '<Button-1>', proc { }) }

      assert_equal baseline, app.interp.callback_ids.length,
        "rebinding should replace, not accumulate, the registered callback"
    end
  end

  def test_tag_unbind_via_empty_script_releases_callback
    assert_tk_app("clearing a tag binding via raw app.command should release the registered callback") do
      app.command(:text, '.txt3')
      baseline = app.interp.callback_ids.length

      app.command('.txt3', 'tag', 'bind', 'mytag', '<Button-1>', proc { })
      assert_equal baseline + 1, app.interp.callback_ids.length, "tag bind should register one callback"

      app.command('.txt3', 'tag', 'bind', 'mytag', '<Button-1>', '')

      assert_equal baseline, app.interp.callback_ids.length, "clearing the binding should release the callback"
    end
  end

  def test_tag_delete_releases_callbacks
    assert_tk_app("deleting a tag via raw app.command should release all of its bound callbacks") do
      app.command(:text, '.txt4')
      baseline = app.interp.callback_ids.length

      app.command('.txt4', 'tag', 'bind', 'mytag', '<Button-1>', proc { })
      app.command('.txt4', 'tag', 'bind', 'mytag', '<Key-a>', proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length, "tag bind should register two callbacks"

      app.command('.txt4', 'tag', 'delete', 'mytag')

      assert_equal baseline, app.interp.callback_ids.length,
        "tag delete should release all of the deleted tag's callbacks"
    end
  end

  def test_tag_delete_does_not_affect_other_tags
    assert_tk_app("deleting one tag via raw app.command should not release another tag's callback") do
      app.command(:text, '.txt5')
      baseline = app.interp.callback_ids.length

      app.command('.txt5', 'tag', 'bind', 'tag_a', '<Button-1>', proc { })
      app.command('.txt5', 'tag', 'bind', 'tag_b', '<Button-1>', proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length

      app.command('.txt5', 'tag', 'delete', 'tag_a')

      assert_equal baseline + 1, app.interp.callback_ids.length,
        "only tag_a's callback should be released"
    end
  end

  def test_destroy_releases_all_tracked_tag_callbacks
    assert_tk_app("destroying a text widget should release all tag callbacks registered via raw app.command") do
      app.command(:text, '.txt6')
      baseline = app.interp.callback_ids.length

      app.command('.txt6', 'tag', 'bind', 'mytag', '<Button-1>', proc { })
      app.command('.txt6', 'tag', 'bind', 'othertag', '<Key-a>', proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length

      app.destroy('.txt6')

      assert_equal baseline, app.interp.callback_ids.length,
        "destroy should release all tracked tag callbacks"
    end
  end
end
