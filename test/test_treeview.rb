# frozen_string_literal: true

# Tests for ttk::treeview callback cleanup across its two independent leak
# surfaces:
#
# - Tag bindings (tag_bind/tag_unbind/tag_delete) come from Teek::TagBindable
#   (shared with Text - confirmed byte-identical Tcl shape via tag bind/tag
#   names on both widgets), so this suite doesn't re-prove the shared
#   mechanism as exhaustively as test_text_tags.rb already does - just that
#   it really works on a treeview too.
# - Column heading commands (#heading) are a separate, option-replacement
#   shaped surface, tracked per column so two columns' commands can't
#   collide - this suite covers that in full.
#
# Interp#callback_ids is a plain reader on the interpreter's callback
# table - see also test_bind.rb, test_menu.rb, test_text_tags.rb.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestTreeview < Minitest::Test
  include TeekTestHelper

  # -- tag bindings (shared TagBindable mechanism) ---------------------------

  def test_tag_bind_fires_for_the_focused_item
    assert_tk_app("tag_bind should fire for the item that currently has treeview focus") do
      app.show
      tv = app.create_widget('ttk::treeview')
      tv.pack
      item = tv.command(:insert, '', :end, text: 'Row 1', tags: 'important')

      fired = false
      tv.tag_bind('important', 'Key-a') { fired = true }

      tv.command(:focus, item)
      app.tcl_eval("focus -force #{tv.path}")
      app.update
      app.tcl_eval("event generate #{tv.path} <Key-a>")
      app.update

      assert fired, "tag binding did not fire"
    end
  end

  def test_tag_bind_rebind_does_not_leak_callbacks
    assert_tk_app("rebinding the same tag+event should not grow callback count") do
      tv = app.create_widget('ttk::treeview')

      tv.tag_bind('mytag', 'Button-1') { }
      baseline = app.interp.callback_ids.length

      5.times { tv.tag_bind('mytag', 'Button-1') { } }

      assert_equal baseline, app.interp.callback_ids.length,
        "rebinding should replace, not accumulate, the registered callback"
    end
  end

  def test_tag_delete_releases_callbacks
    assert_tk_app("tag_delete should release that tag's bound callbacks") do
      tv = app.create_widget('ttk::treeview')
      baseline = app.interp.callback_ids.length

      tv.tag_bind('mytag', 'Button-1') { }
      assert_equal baseline + 1, app.interp.callback_ids.length

      tv.tag_delete('mytag')

      assert_equal baseline, app.interp.callback_ids.length
    end
  end

  # -- column heading commands ------------------------------------------------

  def test_heading_command_still_fires
    assert_tk_app("a tracked heading command should still actually fire") do
      fired = false
      tv = app.create_widget('ttk::treeview', columns: 'col1')
      tv.heading('#0', text: 'Tree', command: proc { fired = true })

      # Tk has no "invoke this heading" command - read back the embedded
      # script and eval it directly, mirroring what Tk itself runs on a
      # real header click.
      script = app.tcl_eval("#{tv.path} heading #0 -command")
      app.tcl_eval(script)

      assert fired, "heading command did not fire"
    end
  end

  def test_heading_columns_tracked_independently
    assert_tk_app("two columns' heading commands should be tracked independently") do
      tv = app.create_widget('ttk::treeview', columns: 'col1 col2')
      baseline = app.interp.callback_ids.length

      tv.heading('#0', text: 'Tree', command: proc { })
      tv.heading('col1', text: 'One', command: proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length,
        "both columns' heading commands should register their own callback"

      tv.heading('#0', text: 'Tree', command: proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length,
        "replacing #0's heading command should not touch col1's"
    end
  end

  def test_heading_command_replace_releases_old_callback
    assert_tk_app("reconfiguring a column's heading command should release the old callback") do
      tv = app.create_widget('ttk::treeview', columns: 'col1')
      tv.heading('col1', text: 'One', command: proc { })
      baseline = app.interp.callback_ids.length

      tv.heading('col1', text: 'One', command: proc { })

      assert_equal baseline, app.interp.callback_ids.length,
        "reconfiguring should replace, not accumulate, the tracked callback"
    end
  end

  def test_heading_without_command_kwarg_does_not_affect_tracking
    assert_tk_app("a heading call that doesn't touch command: should not affect tracked callbacks") do
      tv = app.create_widget('ttk::treeview', columns: 'col1')
      tv.heading('col1', text: 'One', command: proc { })
      baseline = app.interp.callback_ids.length

      tv.heading('col1', text: 'One (renamed)')

      assert_equal baseline, app.interp.callback_ids.length,
        "changing only text: should not release the still-live command"
    end
  end

  # -- destroy releases both surfaces -----------------------------------------

  def test_destroy_releases_both_tag_and_heading_callbacks
    assert_tk_app("destroying a treeview should release both tag and heading callbacks") do
      tv = app.create_widget('ttk::treeview', columns: 'col1')
      baseline = app.interp.callback_ids.length

      tv.tag_bind('mytag', 'Button-1') { }
      tv.heading('col1', text: 'One', command: proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length

      tv.destroy

      assert_equal baseline, app.interp.callback_ids.length,
        "destroy should release tracked callbacks from both surfaces"
    end
  end
end
