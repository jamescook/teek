# frozen_string_literal: true

# Tests for canvas item-binding callback tracking through plain
# app.command() calls - there's no separate wrapper method to know about.
#
# Canvas items aren't windows (only the canvas itself is), so a bound
# item's callback never fires <Destroy> on its own, and `canvas delete`
# is silent - same leak shape menu entries have. Unlike menu/tag bind,
# canvas has no "list every live binding" enumeration command, so
# tracking can't do a full-scan reconcile; it re-queries only the
# (tagOrId, sequence) keys it already knows about via `canvas bind
# tagOrId sequence` (the 2-arg read form) after every bind/delete call.
#
# A binding on a numeric item id is released when that item is deleted.
# A binding on a tag is NOT released by deleting a tagged item - the tag
# itself isn't a window or an item, so its binding-table entry persists
# independent of which (if any) items currently carry that tag.
#
# Interp#callback_ids is a plain reader on the interpreter's callback
# table - see also test_bind.rb, test_menu.rb, test_text_tags.rb.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestCanvasBindings < Minitest::Test
  include TeekTestHelper

  def test_bind_fires_for_item
    assert_tk_app("a proc bound to an item id via raw app.command should still actually fire") do
      app.command(:canvas, '.cvs1')
      item = app.command('.cvs1', :create, :rectangle, 0, 0, 50, 50)

      fired = false
      app.command('.cvs1', :bind, item, '<Button-1>', proc { fired = true })

      # Tk has no "invoke this item binding" command - read back the
      # embedded script and eval it directly, mirroring what Tk itself
      # runs when the item is actually clicked.
      script = app.tcl_eval(".cvs1 bind #{item} <Button-1>")
      app.tcl_eval(script)

      assert fired, "item binding did not fire"
    end
  end

  def test_rebind_does_not_leak_callbacks
    assert_tk_app("rebinding the same item+event via raw app.command should not grow callback count") do
      app.command(:canvas, '.cvs2')
      item = app.command('.cvs2', :create, :rectangle, 0, 0, 50, 50)

      app.command('.cvs2', :bind, item, '<Button-1>', proc { })
      baseline = app.interp.callback_ids.length

      5.times { app.command('.cvs2', :bind, item, '<Button-1>', proc { }) }

      assert_equal baseline, app.interp.callback_ids.length,
        "rebinding should replace, not accumulate, the registered callback"
    end
  end

  def test_unbind_via_empty_script_releases_callback
    assert_tk_app("clearing an item binding via raw app.command should release the callback") do
      app.command(:canvas, '.cvs3')
      item = app.command('.cvs3', :create, :rectangle, 0, 0, 50, 50)
      baseline = app.interp.callback_ids.length

      app.command('.cvs3', :bind, item, '<Button-1>', proc { })
      assert_equal baseline + 1, app.interp.callback_ids.length, "bind should register one callback"

      app.command('.cvs3', :bind, item, '<Button-1>', '')

      assert_equal baseline, app.interp.callback_ids.length, "clearing the binding should release the callback"
    end
  end

  def test_item_delete_releases_its_binding_callback
    assert_tk_app("deleting a bound item via raw app.command should release its callback") do
      app.command(:canvas, '.cvs4')
      item = app.command('.cvs4', :create, :rectangle, 0, 0, 50, 50)
      baseline = app.interp.callback_ids.length

      app.command('.cvs4', :bind, item, '<Button-1>', proc { })
      assert_equal baseline + 1, app.interp.callback_ids.length

      app.command('.cvs4', :delete, item)

      assert_equal baseline, app.interp.callback_ids.length,
        "deleting the bound item should release its tracked callback"
    end
  end

  def test_item_delete_releases_a_binding_with_percent_substitutions
    assert_tk_app("deleting an item bound with %-substitution codes should still release its callback") do
      app.command(:canvas, '.cvs4b')
      item = app.command('.cvs4b', :create, :rectangle, 0, 0, 50, 50)
      baseline = app.interp.callback_ids.length

      app.command('.cvs4b', :bind, item, '<B1-Motion>', proc { |*| }, '%x', '%y')
      assert_equal baseline + 1, app.interp.callback_ids.length

      app.command('.cvs4b', :delete, item)

      assert_equal baseline, app.interp.callback_ids.length,
        "deleting the bound item should release its tracked callback even with %-substitution args"
    end
  end

  def test_tag_binding_survives_item_deletion
    assert_tk_app("a tag binding via raw app.command should survive deleting the tagged item") do
      app.command(:canvas, '.cvs5')
      item = app.command('.cvs5', :create, :rectangle, 0, 0, 50, 50, tags: 'mytag')
      baseline = app.interp.callback_ids.length

      app.command('.cvs5', :bind, 'mytag', '<Button-1>', proc { })
      assert_equal baseline + 1, app.interp.callback_ids.length

      app.command('.cvs5', :delete, item)

      assert_equal baseline + 1, app.interp.callback_ids.length,
        "deleting the item should not release its tag's still-live binding"
    end
  end

  def test_item_and_tag_bindings_tracked_independently
    assert_tk_app("an item id binding and a tag binding via raw app.command should be tracked independently") do
      app.command(:canvas, '.cvs6')
      item1 = app.command('.cvs6', :create, :rectangle, 0, 0, 50, 50)
      app.command('.cvs6', :create, :rectangle, 60, 0, 110, 50, tags: 'mytag')
      baseline = app.interp.callback_ids.length

      app.command('.cvs6', :bind, item1, '<Button-1>', proc { })
      app.command('.cvs6', :bind, 'mytag', '<Button-1>', proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length,
        "both the item and the tag binding should register their own callback"

      app.command('.cvs6', :bind, item1, '<Button-1>', proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length,
        "replacing item1's binding should not touch the tag's"
    end
  end

  def test_destroy_releases_all_tracked_callbacks
    assert_tk_app("destroying a canvas should release all its tracked item/tag binding callbacks") do
      app.command(:canvas, '.cvs7')
      item = app.command('.cvs7', :create, :rectangle, 0, 0, 50, 50, tags: 'mytag')
      baseline = app.interp.callback_ids.length

      app.command('.cvs7', :bind, item, '<Button-1>', proc { })
      app.command('.cvs7', :bind, 'mytag', '<Key-a>', proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length

      app.destroy('.cvs7')

      assert_equal baseline, app.interp.callback_ids.length,
        "destroy should release all tracked item and tag binding callbacks"
    end
  end
end
