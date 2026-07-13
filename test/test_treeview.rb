# frozen_string_literal: true

# Tests for ttk::treeview callback tracking across its two independent leak
# surfaces, both reached through plain app.command() calls - there's no
# separate wrapper method to know about.
#
# - Tag bindings: recognized by the shared text/treeview tag-bind
#   interceptor (byte-identical Tcl shape to Text's) - this suite doesn't
#   re-prove the shared mechanism as exhaustively as test_text_tags.rb
#   already does, just that it really works on a treeview too.
# - Column heading commands are a plain widget-option shape (`heading col
#   command: proc{}`), handled by app.command's generic option-callback
#   tracking - the column is part of the tracking key, so two columns'
#   commands can't collide - this suite covers that in full.
#
# Interp#callback_ids is a plain reader on the interpreter's callback
# table - see also test_bind.rb, test_menu.rb, test_text_tags.rb.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestTreeview < Minitest::Test
  include TeekTestHelper

  # -- tag bindings -----------------------------------------------------------

  def test_tag_bind_fires_for_the_focused_item
    assert_tk_app("a tag binding added via raw app.command should fire for the item that currently has treeview focus") do
      app.show
      app.command('ttk::treeview', '.tv1')
      app.command(:pack, '.tv1')
      item = app.command('.tv1', :insert, '', :end, text: 'Row 1', tags: 'important')

      fired = false
      app.command('.tv1', 'tag', 'bind', 'important', '<Key-a>', proc { fired = true })

      app.command('.tv1', :focus, item)
      app.tcl_eval("focus -force .tv1")
      app.update
      app.tcl_eval("event generate .tv1 <Key-a>")
      app.update

      assert fired, "tag binding did not fire"
    end
  end

  def test_tag_bind_rebind_does_not_leak_callbacks
    assert_tk_app("rebinding the same tag+event via raw app.command should not grow callback count") do
      app.command('ttk::treeview', '.tv2')

      app.command('.tv2', 'tag', 'bind', 'mytag', '<Button-1>', proc { })
      baseline = app.interp.callback_ids.length

      5.times { app.command('.tv2', 'tag', 'bind', 'mytag', '<Button-1>', proc { }) }

      assert_equal baseline, app.interp.callback_ids.length,
        "rebinding should replace, not accumulate, the registered callback"
    end
  end

  def test_tag_delete_releases_callbacks
    assert_tk_app("deleting a tag via raw app.command should release that tag's bound callbacks") do
      # ttk::treeview's `tag delete` doesn't exist before Tcl/Tk 9.0 - the
      # 8.6-available `tag remove` is not a substitute (it only detaches
      # a tag from items; it doesn't touch the tag's own bindings/config
      # the way `tag delete` does; confirmed against ttkTreeview.c). On
      # 8.6, a treeview tag's bindings are only released when the widget
      # itself is destroyed.
      skip "ttk::treeview tag delete requires Tcl/Tk 9.0+" if tcl_major_version < 9

      app.command('ttk::treeview', '.tv3')
      baseline = app.interp.callback_ids.length

      app.command('.tv3', 'tag', 'bind', 'mytag', '<Button-1>', proc { })
      assert_equal baseline + 1, app.interp.callback_ids.length

      app.command('.tv3', 'tag', 'delete', 'mytag')

      assert_equal baseline, app.interp.callback_ids.length
    end
  end

  # -- column heading commands ------------------------------------------------

  def test_heading_command_still_fires
    assert_tk_app("a heading command set via raw app.command should still actually fire") do
      fired = false
      app.command('ttk::treeview', '.tv4', columns: 'col1')
      app.command('.tv4', 'heading', '#0', text: 'Tree', command: proc { fired = true })

      # Tk has no "invoke this heading" command - read back the embedded
      # script and eval it directly, mirroring what Tk itself runs on a
      # real header click.
      script = app.tcl_eval(".tv4 heading #0 -command")
      app.tcl_eval(script)

      assert fired, "heading command did not fire"
    end
  end

  def test_heading_columns_tracked_independently
    assert_tk_app("two columns' heading commands set via raw app.command should be tracked independently") do
      app.command('ttk::treeview', '.tv5', columns: 'col1 col2')
      baseline = app.interp.callback_ids.length

      app.command('.tv5', 'heading', '#0', text: 'Tree', command: proc { })
      app.command('.tv5', 'heading', 'col1', text: 'One', command: proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length,
        "both columns' heading commands should register their own callback"

      app.command('.tv5', 'heading', '#0', text: 'Tree', command: proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length,
        "replacing #0's heading command should not touch col1's"
    end
  end

  def test_heading_command_replace_releases_old_callback
    assert_tk_app("reconfiguring a column's heading command via raw app.command should release the old callback") do
      app.command('ttk::treeview', '.tv6', columns: 'col1')
      app.command('.tv6', 'heading', 'col1', text: 'One', command: proc { })
      baseline = app.interp.callback_ids.length

      app.command('.tv6', 'heading', 'col1', text: 'One', command: proc { })

      assert_equal baseline, app.interp.callback_ids.length,
        "reconfiguring should replace, not accumulate, the tracked callback"
    end
  end

  def test_heading_without_command_kwarg_does_not_affect_tracking
    assert_tk_app("a heading call that doesn't touch command: should not affect tracked callbacks") do
      app.command('ttk::treeview', '.tv7', columns: 'col1')
      app.command('.tv7', 'heading', 'col1', text: 'One', command: proc { })
      baseline = app.interp.callback_ids.length

      app.command('.tv7', 'heading', 'col1', text: 'One (renamed)')

      assert_equal baseline, app.interp.callback_ids.length,
        "changing only text: should not release the still-live command"
    end
  end

  # -- destroy releases both surfaces -----------------------------------------

  def test_destroy_releases_both_tag_and_heading_callbacks
    assert_tk_app("destroying a treeview should release both tag and heading callbacks registered via raw app.command") do
      app.command('ttk::treeview', '.tv8', columns: 'col1')
      baseline = app.interp.callback_ids.length

      app.command('.tv8', 'tag', 'bind', 'mytag', '<Button-1>', proc { })
      app.command('.tv8', 'heading', 'col1', text: 'One', command: proc { })
      assert_equal baseline + 2, app.interp.callback_ids.length

      app.destroy('.tv8')

      assert_equal baseline, app.interp.callback_ids.length,
        "destroy should release tracked callbacks from both surfaces"
    end
  end
end
