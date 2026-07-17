# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Handle#modal/#grab_release are thin delegates to Teek::Window (see base
# teek's own test_modal.rb) - no grab/focus/destroy-safety-net logic is
# reimplemented here. These confirm the DSL layer actually wires through
# to the real thing end to end, using the same grab current/status style
# base teek's own tests use.
#
# A ui.window is withdrawn (not viewable) until shown - Tk's own `grab
# set` requires a viewable window, so every test below calls .show first,
# the same way a real caller would before making a window modal.
class TestModalHandle < Minitest::Test
  include TeekTestHelper

  tk_test "a window handle's modal should grab input and force focus onto it" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Modal Handle Test') { |ui| ui.window(:settings) }
    session.run_async
    session.app.update

    session[:settings].show
    session[:settings].modal

    path = session[:settings].path
    assert_equal path, session.app.tcl_eval("grab current #{path}")
    assert_equal path, session.app.tcl_eval('focus')

    session[:settings].grab_release
  end

  tk_test "grab_release should clear the grab set by modal" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Modal Handle Test') { |ui| ui.window(:settings) }
    session.run_async
    session.app.update

    session[:settings].show
    session[:settings].modal
    session[:settings].grab_release

    path = session[:settings].path
    assert_equal '', session.app.tcl_eval("grab current #{path}")
  end

  tk_test "modal should release the grab immediately if its setup block raises, not leave it stuck" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Modal Handle Test') { |ui| ui.window(:settings) }
    session.run_async
    session.app.update
    session[:settings].show

    path = session[:settings].path
    error = assert_raises(RuntimeError) { session[:settings].modal { raise 'boom' } }
    assert_equal 'boom', error.message

    assert_equal '', session.app.tcl_eval("grab current #{path}")
  end

  tk_test "modal's grab should still be held after a successful setup block - released explicitly, not automatically" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Modal Handle Test') { |ui| ui.window(:settings) }
    session.run_async
    session.app.update
    session[:settings].show

    ran = false
    session[:settings].modal { ran = true }

    assert ran, "the setup block should run"
    path = session[:settings].path
    assert_equal path, session.app.tcl_eval("grab current #{path}")

    session[:settings].grab_release
  end

  tk_test "modal should release the grab if its window is destroyed without an explicit grab_release" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Modal Handle Test') { |ui| ui.window(:settings) }
    session.run_async
    session.app.update
    session[:settings].show

    path = session[:settings].path
    session[:settings].modal
    assert_equal path, session.app.tcl_eval("grab current #{path}")

    session.app.destroy(path)

    assert_equal '', session.app.tcl_eval('grab current')
  end

  tk_test "modal on a non-window handle should raise a clear error" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Modal Handle Test') { |ui| ui.button(:go, text: 'Go') }
    session.run_async
    session.app.update

    error = assert_raises(ArgumentError) { session[:go].modal }
    assert_match(/window/i, error.message)
  end

  tk_test "grab_release on a non-window handle should raise a clear error" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Modal Handle Test') { |ui| ui.button(:go, text: 'Go') }
    session.run_async
    session.app.update

    error = assert_raises(ArgumentError) { session[:go].grab_release }
    assert_match(/window/i, error.message)
  end
end
