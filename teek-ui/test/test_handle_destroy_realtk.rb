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

  def test_a_close_button_destroying_its_own_containing_window_does_not_error
    assert_tk_app("a close button tearing down its own containing window via destroy! should not race ttk's own internal same-click bindings") do
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

      session.app.destroy
    end
  end

  def test_destroy_outside_any_callback_is_synchronous
    assert_tk_app("destroy! called outside a callback (default defer: nil) should tear down immediately, with no update needed") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Destroy Defer Test') { |ui| ui.panel(:box) }
      session.run_async
      session.app.update

      path = session[:box].path
      session[:box].destroy!

      refute session.app.winfo.exists?(path), "destroy! outside a callback should destroy synchronously, before the call returns"

      session.app.destroy
    end
  end

  def test_defer_false_forces_synchronous_destroy_even_inside_a_callback
    assert_tk_app("destroy!(defer: false) should force an immediate synchronous destroy even from inside a callback") do
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

      session.app.destroy
    end
  end

  def test_defer_true_forces_deferred_destroy_even_outside_a_callback
    assert_tk_app("destroy!(defer: true) should defer even outside a callback - the widget is still there right after the call, gone after the next idle") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Destroy Defer Test') { |ui| ui.panel(:box) }
      session.run_async
      session.app.update

      path = session[:box].path
      session[:box].destroy!(defer: true)

      assert session.app.winfo.exists?(path), "a deferred destroy should not have run yet, synchronously, right after the call"

      session.app.update

      refute session.app.winfo.exists?(path), "the deferred destroy should have run by the next update (which processes idle callbacks)"

      session.app.destroy
    end
  end

  def test_calling_destroy_twice_while_a_deferred_destroy_is_still_pending_is_safe
    assert_tk_app("calling destroy! a second time on the same handle before its own deferred teardown has run should not raise or double-schedule") do
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

      session.app.destroy
    end
  end

  def test_destroying_an_ancestor_then_a_descendant_is_safe
    assert_tk_app("destroying an ancestor's handle, then a descendant's own handle, should not raise even though the descendant's own Tk widget is already gone") do
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

      session.app.destroy
    end
  end

  def test_a_deferred_destroy_releases_its_callback_by_the_next_update
    assert_tk_app("a deferred destroy should release its widget's callback once the idle pass runs, same as a synchronous destroy does immediately") do
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

      session.app.destroy
    end
  end
end
