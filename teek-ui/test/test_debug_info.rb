# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Aggregate callback/leak diagnostics: Session#debug_info (programmatic)
# and run/run_async's debug: true (prints the same summary to STDERR).
# Both are thin wrappers over Teek::CallbackRegistry#counts_by_tag,
# which already has its own dedicated, headless coverage in teek core's
# own test/test_callback_registry.rb - these focus on teek-ui's own
# wiring (realize-only guard, friendly key names, the debug: printout),
# not re-proving the registry's own counting logic.
class TestDebugInfo < Minitest::Test
  include TeekTestHelper

  tk_test "session.debug_info should raise before realize, matching every other realize-only diagnostic" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Debug Info Test')

    assert_raises(Teek::UI::NotRealizedError) { session.debug_info }
  end

  tk_test "debug_info should count a wired on_click as an event binding" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Debug Info Test') { |ui| ui.button(:go, text: 'Go').on_click { } }
    session.run_async
    session.app.update

    assert_equal 1, session.debug_info[:event_bindings]

    session.app.destroy
  end

  tk_test "debug_info should count a menu item's own command callback as a menu entry" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Debug Info Test') do |ui|
      ui.menu_bar { |mb| mb.menu(:file, label: 'File') { |f| f.item(label: 'Open') { } } }
    end
    session.run_async
    session.app.update

    assert_equal 1, session.debug_info[:menu_entries]

    session.app.destroy
  end

  tk_test "debug_info should count a canvas item's on_click as a canvas item bind" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Debug Info Test') { |ui| ui.canvas(:board, width: 100, height: 100) }
    session.run_async
    session.app.update
    session[:board].oval(0, 0, 10, 10).on_click { }

    assert_equal 1, session.debug_info[:canvas_item_binds]

    session.app.destroy
  end

  tk_test "debug_info should count a bare -command option (e.g. from a Var bind:) as a widget-option callback" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Debug Info Test') do |ui|
      wrap = ui.var(false)
      ui.checkbox(:agree, bind: wrap)
    end
    session.run_async
    session.app.update
    # a plain -variable bind doesn't register a Ruby callback on its
    # own - drive a real -command option through the escape hatch to
    # exercise this category directly, matching what App#command's own
    # -command handling (the :widget_option tag) actually tracks.
    session.app.command(session[:agree].path, :configure, command: -> { })

    assert_equal 1, session.debug_info[:widget_option_callbacks]

    session.app.destroy
  end

  tk_test "creating N event bindings then destroying those widgets should return the count to baseline, not just count monotonically upward" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Debug Info Test') { |ui| ui.panel(:host) }
    session.run_async
    session.app.update
    baseline = session.debug_info[:event_bindings] || 0

    handles = []
    session.add(:host) do |a|
      3.times { |i| handles << a.button(text: "Item #{i}").on_click { } }
    end
    session.app.update

    assert_equal baseline + 3, session.debug_info[:event_bindings]

    handles.each { |h| h.destroy!(defer: false) }
    session.app.update

    assert_equal baseline, session.debug_info[:event_bindings] || 0,
      "destroying the widgets should release their callbacks, bringing the count back to baseline"

    session.app.destroy
  end

  tk_test "run_async(debug: true) should print the same grouped summary to stderr right after realize" do
    require 'teek/ui'

    _out, err = capture_io do
      session = Teek::UI.app(title: 'Debug Info Test') { |ui| ui.button(:go, text: 'Go').on_click { } }
      session.run_async(debug: true)
      session.app.destroy
    end

    assert_match(/event_bindings/, err)
    assert_match(/1/, err)
  end

  tk_test "run_async with no debug: (default false) should print nothing" do
    require 'teek/ui'

    _out, err = capture_io do
      session = Teek::UI.app(title: 'Debug Info Test') { |ui| ui.button(:go, text: 'Go').on_click { } }
      session.run_async
      session.app.destroy
    end

    assert_empty err
  end

  # #run's own "print before and after mainloop" isn't covered by a
  # live, blocking-mainloop test here - there's no existing precedent in
  # this suite for scheduling a self-destroy to unblock #run from inside
  # a test, and #run/#run_async share the exact same
  # realize -> show -> print_debug_info sequence up to the point #run
  # additionally calls #mainloop, which run_async's own debug: tests
  # above already cover. The second print (after mainloop returns) is
  # the same print_debug_info call, unconditionally placed right after
  # the #mainloop line - see Session#run's own source.
end
