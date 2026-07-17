# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Real-Tk coverage of Handle#destroy!'s auto-defer behavior - needs a
# genuine Tcl callback dispatch to exercise (Teek.in_callback? reflects
# the real interpreter's live callback depth, meaningless without one),
# so this can't be headless like test_lazy_realize.rb's Realizer-level
# coverage.
class TestHandleDestroyRealTk < Minitest::Test
  include TeekTestHelper

  tk_test "a close button tearing down its own containing window via destroy! should not race ttk's own internal same-click bindings" do
    require 'teek/ui'

    handle = nil
    session = Teek::UI.app(title: 'Destroy Defer Test') do |ui|
      handle = ui.window(:dialog, modal: true) { |w| w.button(:close, text: 'Close').on_click { handle.destroy! } }
    end
    session.run_async
    session.app.update

    # the "invalid command name" hazard this fixes only ever surfaced
    # via Tcl's bgerror (a background/asynchronous error), never as a
    # Ruby exception raised back through event generate - override it
    # to capture the message instead of letting the default handler
    # print/ignore it.
    session.app.tcl_eval(<<~'TCL')
      proc _test_bgerror {msg opts} {
        set ::bgerror_msg $msg
      }
      interp bgerror {} _test_bgerror
      set ::bgerror_msg {}
    TCL

    session.app.tcl_eval("event generate #{handle.path}.close <Button-1>")
    session.app.tcl_eval("event generate #{handle.path}.close <ButtonRelease-1>")
    session.app.update

    bgerror = session.app.tcl_eval('set ::bgerror_msg')
    assert_empty bgerror, "no Tcl-level error should have been raised by ttk's own bindings running against an already-destroyed widget"
  end

  tk_test "destroy! called outside a callback (default defer: nil) should tear down immediately, with no update needed" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Destroy Defer Test') { |ui| ui.panel(:box) }
    session.run_async
    session.app.update

    path = session[:box].path
    session[:box].destroy!

    refute session.app.winfo.exists?(path), "destroy! outside a callback should destroy synchronously, before the call returns"
  end

  tk_test "destroy!(defer: false) should force an immediate synchronous destroy even from inside a callback" do
    require 'teek/ui'

    handle = nil
    session = Teek::UI.app(title: 'Destroy Defer Test') do |ui|
      ui.panel(:host) do |p|
        handle = p.panel(:box)
        p.button(:go, text: 'Go').on_click { handle.destroy!(defer: false) }
      end
    end
    session.run_async
    session.app.update
    path = handle.path

    session.app.tcl_eval("event generate #{session[:go].path} <Button-1>")
    # deliberately NOT calling session.app.update before checking - a
    # forced synchronous destroy should already be gone, without
    # needing an idle pass to catch up.
    refute session.app.winfo.exists?(path)
  end

  tk_test "destroy!(defer: true) should defer even outside a callback - the widget is still there right after the call, gone after the next idle" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Destroy Defer Test') { |ui| ui.panel(:box) }
    session.run_async
    session.app.update

    path = session[:box].path
    session[:box].destroy!(defer: true)

    assert session.app.winfo.exists?(path), "a deferred destroy should not have run yet, synchronously, right after the call"

    session.app.update

    refute session.app.winfo.exists?(path), "the deferred destroy should have run by the next update (which processes idle callbacks)"
  end

  tk_test "calling destroy! a second time on the same handle before its own deferred teardown has run should not raise or double-schedule" do
    require 'teek/ui'

    handle = nil
    session = Teek::UI.app(title: 'Destroy Defer Test') do |ui|
      ui.panel(:host) do |p|
        handle = p.panel(:box)
        p.button(:go, text: 'Go').on_click {
          handle.destroy!
          handle.destroy! # same handle, still pending - must not raise
        }
      end
    end
    session.run_async
    session.app.update
    path = handle.path

    session.app.tcl_eval("event generate #{session[:go].path} <Button-1>")
    session.app.update

    refute session.app.winfo.exists?(path)
  end

  tk_test "destroying an ancestor's handle, then a descendant's own handle, should not raise even though the descendant's own Tk widget is already gone" do
    require 'teek/ui'

    parent_handle = nil
    child_handle = nil
    session = Teek::UI.app(title: 'Destroy Defer Test') do |ui|
      ui.panel(:host) do |p|
        parent_handle = p.panel(:box) { |b| child_handle = b.button(:inner, text: 'Inner') }
      end
    end
    session.run_async
    session.app.update

    parent_handle.destroy!(defer: false)
    # the descendant's OWN Node#realized is untouched by the ancestor's
    # destroy (only the ancestor's own node gets reset) - its Tk widget
    # is gone already, but Tcl's own destroy command is a documented
    # no-op on an already-gone path, so this should not raise.
    child_handle.destroy!(defer: false)
  end

  tk_test "a deferred destroy should release its widget's callback once the idle pass runs, same as a synchronous destroy does immediately" do
    require 'teek/ui'

    handle = nil
    session = Teek::UI.app(title: 'Destroy Defer Test') do |ui|
      ui.panel(:host) do |p|
        handle = p.panel(:box) { |b| b.button(:a, text: 'A').on_click { } }
      end
    end
    session.run_async
    session.app.update
    with_button_baseline = session.app.interp.callback_ids.length

    handle.destroy!(defer: true)
    # scheduling the deferred teardown itself registers one new
    # after_idle callback - :a's own on_click isn't released yet.
    assert_equal with_button_baseline + 1, session.app.interp.callback_ids.length,
      "a still-pending deferred destroy should not have released :a's callback yet"

    session.app.update

    assert_equal with_button_baseline - 1, session.app.interp.callback_ids.length,
      "once the deferred destroy actually runs, both its own after_idle registration and :a's on_click should be released"
  end

  tk_test "destroy! should remove the destroyed node from its parent's own children, not just clear its Tk-realized state" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Destroy Defer Test') do |ui|
      ui.panel(:host) { |p| p.button(:item, text: 'Item') }
    end
    session.run_async
    session.app.update
    host_node = session.document.find(:host)
    item_node = session.document.find(:item)

    session[:item].destroy!(defer: false)

    refute_includes host_node.children, item_node
  end

  tk_test "destroying a named widget should let a later widget reuse the same name in the same scope, and ui[:name] should be nil in between" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Destroy Defer Test') { |ui| ui.panel(:host) }
    session.run_async
    session.app.update

    session.add(:host) { |a| a.button(:item, text: 'First') }
    session.app.update
    first_path = session[:item].path
    session[:item].destroy!(defer: false)

    assert_nil session[:item], "ui[:item] should be nil once the widget that owned that name is destroyed"

    session.add(:host) { |a| a.button(:item, text: 'Second') }
    session.app.update

    refute_nil session[:item], "a new :item should be addable again under the same name once the old one is gone"
    assert_equal 'Second', session.app.command(session[:item].path, :cget, '-text')
    refute_equal first_path, session[:item].path
  end

  tk_test "repeatedly adding and destroying a plain (non-window) named widget under one shared parent should never crash arrange_children" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Destroy Defer Test') { |ui| ui.panel(:host) }
    session.run_async
    session.app.update

    5.times do |i|
      handle = nil
      session.add(:host) { |a| handle = a.button(:item, text: "Item #{i}") }
      session.app.update
      assert_equal "Item #{i}", session.app.command(handle.path, :cget, '-text')
      handle.destroy!(defer: false)
      session.app.update
    end

    assert_nil session[:item]
    assert_equal 0, session.document.find(:host).children.length
  end

  tk_test "arrange_children should correctly position a new sibling relative to survivors, with no trace of a destroyed sibling" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Destroy Defer Test') do |ui|
      ui.column(:host, gap: 10) { |c| c.button(:first, text: 'First') }
    end
    session.run_async
    session.app.update

    doomed = nil
    session.add(:host) { |a| doomed = a.button(:doomed, text: 'Doomed') }
    session.app.update
    doomed.destroy!(defer: false)
    session.app.update

    session.add(:host) { |a| a.button(:second, text: 'Second') }
    session.app.update

    first_bottom = session.app.winfo.rooty(session[:first].path) + session.app.winfo.height(session[:first].path)
    second_top = session.app.winfo.rooty(session[:second].path)
    assert_equal 10, second_top - first_bottom,
      "the new sibling should be positioned relative to :first, as if :doomed never existed"
  end

  tk_test "Screens#pop already removes its own Entry before returning the handle, so destroy! afterward can't leave anything stale in Screens' own bookkeeping" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Destroy Defer Test') { |ui| ui.panel(:picker) }
    session.run_async
    session.app.update

    session.screens.push(:picker, session[:picker])
    popped = session.screens.pop
    popped.destroy!(defer: false)

    refute session.screens.active?
    assert_nil session.screens.current
    assert_nil session.screens.current_screen
    assert_equal 0, session.screens.size
  end

  tk_test "destroying (and unlinking) an unrelated widget elsewhere in the tree should have zero effect on an already-built menu's own entries/ordering" do
    require 'teek/ui'

    clicked = []
    session = Teek::UI.app(title: 'Destroy Defer Test') do |ui|
      ui.menu_bar do |mb|
        mb.menu(:file, label: 'File') do |f|
          f.item(label: 'One') { clicked << :one }
          f.item(label: 'Two') { clicked << :two }
        end
      end
      ui.panel(:host) { |p| p.button(:item, text: 'Item') }
    end
    session.run_async
    session.app.update

    session[:item].destroy!(defer: false)
    session.app.update

    file_path = session[:file].path
    assert_equal 'One', session.app.command(file_path, :entrycget, 0, '-label')
    assert_equal 'Two', session.app.command(file_path, :entrycget, 1, '-label')

    session.app.tcl_eval("#{file_path} invoke 0")
    session.app.tcl_eval("#{file_path} invoke 1")

    assert_equal [:one, :two], clicked, "menu entries should still fire in their original order, unaffected by an unrelated destroy elsewhere"
  end
end
