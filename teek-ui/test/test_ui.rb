# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

class TestUI < Minitest::Test
  include TeekTestHelper

  tk_test "Teek::UI.app should yield a session and return that same session" do
    require 'teek/ui'

    yielded = nil
    session = Teek::UI.app(title: 'UI Scaffold Test') { |ui| yielded = ui }

    assert_same session, yielded, "the block should receive the same session .app returns"
    assert_kind_of Teek::UI::Session, session
  end

  tk_test "building a session should not construct any Teek::App/Interp until realize" do
    require 'teek/ui'

    baseline = Teek::Interp.instance_count
    Teek::UI.app(title: 'UI Scaffold Test') { |ui| ui.document }

    assert_equal baseline, Teek::Interp.instance_count,
      "Teek::UI.app should not construct an interpreter before #realize/#run/#run_async"
  end

  tk_test "session.document should be a real, empty Document, buildable with no interpreter" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'UI Scaffold Test')

    assert_kind_of Teek::UI::Document, session.document
    assert_equal [], session.document.root.children
  end

  tk_test "session.app should raise a clear error before realize" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'UI Scaffold Test')

    error = assert_raises(Teek::UI::NotRealizedError) { session.app }
    assert_match(/not realized/i, error.message)
  end

  tk_test "session.every/.after declared inside the build block should queue (no NotRealizedError) and actually fire once realized" do
    require 'teek/ui'

    ticks = 0
    fired = false
    session = Teek::UI.app(title: 'Timers Test') do |ui|
      ui.every(10) { ticks += 1 }
      ui.after(10) { fired = true }
    end
    session.run_async

    deadline = Time.now + 2
    session.app.update until (ticks >= 2 && fired) || Time.now > deadline

    assert_operator ticks, :>=, 2, "a build-block ui.every should have ticked after realize, same as a post-realize one"
    assert fired, "a build-block ui.after should have fired after realize, same as a post-realize one"
  end

  tk_test "a timer declared inside the build block and one declared after realize should produce the same runtime behavior" do
    require 'teek/ui'

    queued_ticks = 0
    session = Teek::UI.app(title: 'Timers Test') { |ui| ui.every(10) { queued_ticks += 1 } }
    session.run_async

    post_realize_ticks = 0
    session.every(10) { post_realize_ticks += 1 }

    deadline = Time.now + 2
    session.app.update until (queued_ticks >= 2 && post_realize_ticks >= 2) || Time.now > deadline

    assert_operator queued_ticks, :>=, 2
    assert_operator post_realize_ticks, :>=, 2
  end

  tk_test "session.every should return nil when queued (no live timer object exists yet to hand back)" do
    require 'teek/ui'

    result = nil
    session = Teek::UI.app(title: 'Timers Test') { |ui| result = ui.every(10) { } }
    session.run_async
    session.app.update

    assert_nil result
  end

  tk_test "realize should create the app once and return the same app on repeat calls" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'UI Scaffold Test')
    baseline = Teek::Interp.instance_count

    app1 = session.realize
    app2 = session.realize

    assert_same app1, app2, "realize should be idempotent, not build a second interpreter"
    assert_equal baseline + 1, Teek::Interp.instance_count
  end

  tk_test "session.app after realize should expose the real Teek::App with the title applied" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'UI Scaffold Test')
    session.realize

    assert_kind_of Teek::App, session.app
    assert_equal 'UI Scaffold Test', session.app.wm.title(window: '.')
  end

  tk_test "run_async should realize, show the window, and return the session without entering mainloop" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Run Async Test')
    result = session.run_async

    assert_same session, result

    # run_async deliberately doesn't pump the event loop itself (that's the
    # documented caveat) - the deiconify it issued only becomes visible to
    # winfo after something processes events, same as any real caller's
    # own event-loop-driven flow would need to do.
    session.app.update
    assert session.app.winfo.ismapped?('.'), "run_async should have shown the root window"
  end

  tk_test "ui.every should delegate to App#every and actually tick, once realized" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Timers Test')
    session.run_async
    ticks = 0
    timer = session.every(10) { ticks += 1 }

    deadline = Time.now + 2
    session.app.update until ticks >= 2 || Time.now > deadline

    assert_operator ticks, :>=, 2, "ui.every's block did not tick"
    timer.cancel
  end

  tk_test "ui.after should delegate to App#after, once realized" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Timers Test')
    session.run_async
    fired = false
    session.after(10) { fired = true }

    deadline = Time.now + 2
    session.app.update until fired || Time.now > deadline

    assert fired, "ui.after's block did not fire"
  end

  tk_test "session's dialog methods should raise a clear error before realize, not queue" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Dialogs Test')

    assert_raises(Teek::UI::NotRealizedError) { session.open_file }
    assert_raises(Teek::UI::NotRealizedError) { session.save_file }
    assert_raises(Teek::UI::NotRealizedError) { session.message(message: 'Hi') }
    assert_raises(Teek::UI::NotRealizedError) { session.choose_color }
    assert_raises(Teek::UI::NotRealizedError) { session.choose_dir }
  end

  tk_test "session.open_file should forward every option to App#choose_open_file under the right flag" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Dialogs Test')
    session.run_async
    session.app.tcl_eval(<<~TCL)
      proc tk_getOpenFile {args} {
        set ::last_call $args
        return {/tmp/picked.png}
      }
    TCL

    result = session.open_file(
      initialdir: '/tmp/open', initialfile: 'pick.png', title: 'Open It', multiple: true, parent: '.mywin'
    )

    assert_equal ['/tmp/picked.png'], result, "multiple: true should split Tk's result into an array"
    captured = Hash[*session.app.split_list(session.app.tcl_eval('set ::last_call'))]
    assert_equal(
      { '-initialdir' => '/tmp/open', '-initialfile' => 'pick.png', '-title' => 'Open It',
        '-parent' => '.mywin', '-multiple' => '1' },
      captured
    )
  end

  tk_test "session.save_file should forward every option to App#choose_save_file under the right flag" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Dialogs Test')
    session.run_async
    session.app.tcl_eval(<<~TCL)
      proc tk_getSaveFile {args} {
        set ::last_call $args
        return {/tmp/out.png}
      }
    TCL

    result = session.save_file(
      initialdir: '/tmp/save', initialfile: 'out.png', title: 'Save It',
      defaultextension: '.png', confirmoverwrite: false, parent: '.mywin'
    )

    assert_equal '/tmp/out.png', result
    captured = Hash[*session.app.split_list(session.app.tcl_eval('set ::last_call'))]
    assert_equal(
      { '-initialdir' => '/tmp/save', '-initialfile' => 'out.png', '-title' => 'Save It',
        '-defaultextension' => '.png', '-confirmoverwrite' => '0', '-parent' => '.mywin' },
      captured
    )
  end

  tk_test "session.message should forward every option to App#message_box under the right flag" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Dialogs Test')
    session.run_async
    session.app.tcl_eval(<<~TCL)
      proc tk_messageBox {args} {
        set ::last_call $args
        return {yes}
      }
    TCL

    result = session.message(
      message: 'Sure?', title: 'Confirm', detail: 'Cannot be undone',
      icon: :warning, type: :yesno, default: :no, parent: '.mywin'
    )

    assert_equal :yes, result
    captured = Hash[*session.app.split_list(session.app.tcl_eval('set ::last_call'))]
    assert_equal(
      { '-message' => 'Sure?', '-title' => 'Confirm', '-detail' => 'Cannot be undone',
        '-icon' => 'warning', '-type' => 'yesno', '-default' => 'no', '-parent' => '.mywin' },
      captured
    )
  end

  tk_test "session.choose_color should forward every option to App#choose_color under the right flag" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Dialogs Test')
    session.run_async
    session.app.tcl_eval(<<~TCL)
      proc tk_chooseColor {args} {
        set ::last_call $args
        return {#ff0080}
      }
    TCL

    result = session.choose_color(initial: '#112233', title: 'Pick', parent: '.mywin')

    assert_equal '#ff0080', result
    captured = Hash[*session.app.split_list(session.app.tcl_eval('set ::last_call'))]
    assert_equal({ '-initialcolor' => '#112233', '-title' => 'Pick', '-parent' => '.mywin' }, captured)
  end

  tk_test "session.choose_dir should forward every option to App#choose_dir under the right flag" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Dialogs Test')
    session.run_async
    session.app.tcl_eval(<<~TCL)
      proc tk_chooseDirectory {args} {
        set ::last_call $args
        return {/tmp/some dir}
      }
    TCL

    result = session.choose_dir(initialdir: '/tmp/dir', mustexist: true, title: 'Folder', parent: '.mywin')

    assert_equal '/tmp/some dir', result
    captured = Hash[*session.app.split_list(session.app.tcl_eval('set ::last_call'))]
    assert_equal(
      { '-initialdir' => '/tmp/dir', '-mustexist' => '1', '-title' => 'Folder', '-parent' => '.mywin' },
      captured
    )
  end

  tk_test "a validation failure should prevent any Teek::App/Interp from being constructed at all" do
    require 'teek/ui'

    baseline = Teek::Interp.instance_count
    session = Teek::UI.app(title: 'Validation Test') do |ui|
      ui.grid(:g) do |g|
        g.cell(row: 0, col: 0) { g.label(:a, text: 'A') }
        g.cell(row: 0, col: 0) { g.label(:b, text: 'B') }
      end
    end

    error = assert_raises(Teek::UI::ValidationError) { session.realize }
    assert_match(/row 0, col 0/, error.message)

    assert_equal baseline, Teek::Interp.instance_count,
      "a doomed build should never construct an interpreter, not even one that gets destroyed afterward"
    assert_raises(Teek::UI::NotRealizedError) { session.app }
  end

  tk_test "ui.button/panel/raw/var/menu_bar/context_menu should all raise once the build has closed" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Closed Builder Test')
    session.run_async

    error = assert_raises(Teek::UI::ClosedBuilderError) { session.button(:late, text: 'Too late') }
    assert_match(/session\.add/, error.message)

    assert_raises(Teek::UI::ClosedBuilderError) { session.panel(:late) }
    assert_raises(Teek::UI::ClosedBuilderError) { session.raw { } }
    assert_raises(Teek::UI::ClosedBuilderError) { session.var(1) }
    assert_raises(Teek::UI::ClosedBuilderError) { session.menu_bar }
    assert_raises(Teek::UI::ClosedBuilderError) { session.context_menu }
  end

  tk_test "the closed-builder guard should never fire during the ordinary, still-open initial build" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Closed Builder Test') do |ui|
      ui.button(:go, text: 'Go')
      ui.var(1)
    end
    session.run_async
    session.app.update

    assert session.app.winfo.ismapped?(session[:go].path)
  end

  tk_test "session.add's own block should be exempt from the closed-builder guard" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Closed Builder Test') { |ui| ui.column(:list) }
    session.run_async

    session.add(:list) { |a| a.button(:added, text: 'Added') }
    session.app.update

    assert session.app.winfo.ismapped?(session[:added].path)

    # the guard should still apply to code OUTSIDE session.add, even
    # though it's fine again momentarily while add's own block runs
    assert_raises(Teek::UI::ClosedBuilderError) { session.button(:still_too_late, text: 'Nope') }
  end
end
