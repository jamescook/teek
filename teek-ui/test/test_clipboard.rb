# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# session.clipboard is a thin, realize-only delegation to Teek::Clipboard
# (see teek core's own test/test_clipboard.rb for the underlying set/get/
# clear behavior). What's new to verify at this layer: the delegation
# itself, and that DSL text widgets need no extra wiring at all for
# platform-standard copy/cut/paste - Tk's own class bindings already
# cover it.
class TestClipboard < Minitest::Test
  include TeekTestHelper

  tk_test "session.clipboard should raise a clear error before realize, not queue" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Clipboard Test')

    assert_raises(Teek::UI::NotRealizedError) { session.clipboard }
  end

  tk_test "session.clipboard.set/.get should round-trip, delegating to the underlying app" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Clipboard Test')
    session.run_async

    session.clipboard.set('hello from teek-ui')

    assert_equal 'hello from teek-ui', session.clipboard.get

    session.app.destroy
  end

  tk_test "a DSL text_box should support Ctrl-C copy out of the box - no on_key wiring needed" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Clipboard Test') { |ui| ui.text_box(:field) }
    session.run_async
    session.app.update

    path = session[:field].path
    session.app.command(path, :insert, 0, 'hello world')
    session.app.tcl_eval("#{path} selection range 0 5")
    session.app.tcl_eval("focus -force #{path}")
    session.app.update

    session.clipboard.clear
    session.app.tcl_eval("event generate #{path} <Control-c>")
    session.app.update

    assert_equal 'hello', session.clipboard.get

    session.app.destroy
  end

  tk_test "a DSL text_area should support Ctrl-C copy out of the box - no on_key wiring needed" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Clipboard Test') { |ui| ui.text_area(:notes) }
    session.run_async
    session.app.update

    path = session[:notes].path
    session.app.command(path, :insert, '1.0', 'hello world')
    session.app.tcl_eval("#{path} tag add sel 1.0 1.5")
    session.app.tcl_eval("focus -force #{path}")
    session.app.update

    session.clipboard.clear
    session.app.tcl_eval("event generate #{path} <Control-c>")
    session.app.update

    assert_equal 'hello', session.clipboard.get

    session.app.destroy
  end
end
