# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# ui.toast: a brief, auto-dismissing notification (e.g. "Saved" after a
# save action). Genericized from an SDL2-rendered original that drew its
# own background/text directly to a renderer - this is a real ttk::label,
# floated over the bottom of the window via place, reused across calls
# rather than rebuilt each time (there's only ever one toast on screen).
class TestToast < Minitest::Test
  include TeekTestHelper

  tk_test "session.toast should raise before realize, matching every other realize-only action" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Toast Test')

    assert_raises(Teek::UI::NotRealizedError) { session.toast('Saved') }
  end

  tk_test "toast should create a visible widget carrying the given text" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Toast Test')
    session.run_async

    session.toast('Saved')
    session.app.update

    assert_equal 'Saved', session.app.command('.toast', :cget, '-text')
    assert session.app.winfo.ismapped?('.toast')
  end

  tk_test "toast should auto-dismiss after the given duration, not stay forever" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Toast Test')
    session.run_async

    session.toast('Saved', duration: 30)
    session.app.update
    assert session.app.winfo.ismapped?('.toast'), "should be visible immediately after showing"

    deadline = Time.now + 2
    session.app.update while session.app.winfo.ismapped?('.toast') && Time.now < deadline

    refute session.app.winfo.ismapped?('.toast'), "should have auto-dismissed by now"
  end

  tk_test "toast with no duration: override should still auto-dismiss, using the built-in default" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Toast Test')
    session.run_async

    session.toast('Saved')
    session.app.update
    assert session.app.winfo.ismapped?('.toast')

    deadline = Time.now + 3
    session.app.update while session.app.winfo.ismapped?('.toast') && Time.now < deadline

    refute session.app.winfo.ismapped?('.toast'), "the default duration should have elapsed by now"
  end

  tk_test "a second toast while one is showing should replace it, not create a second widget" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Toast Test')
    session.run_async

    before = session.app.split_list(session.app.tcl_eval('winfo children .')).length

    session.toast('Saved')
    session.app.update
    session.toast('Settings')
    session.app.update

    after = session.app.split_list(session.app.tcl_eval('winfo children .')).length

    assert_equal before + 1, after, "calling toast twice should not leave two separate widgets behind"
    assert_equal 'Settings', session.app.command('.toast', :cget, '-text')
  end

  tk_test "replacing a toast should cancel the earlier one's auto-dismiss - it must not hide the NEW toast early" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Toast Test')
    session.run_async

    session.toast('Saved', duration: 30)
    session.app.update
    session.toast('Settings', duration: 1000)
    session.app.update

    sleep 0.08
    session.app.update

    assert session.app.winfo.ismapped?('.toast'),
      "the first toast's short timer should have been cancelled, not fired and hidden the replacement"
    assert_equal 'Settings', session.app.command('.toast', :cget, '-text')
  end
end
