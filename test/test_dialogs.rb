# frozen_string_literal: true

# Tests for App's safe Tk dialog wrappers (choose_open_file,
# choose_save_file, message_box, choose_color, choose_dir, popup_menu).
#
# Real dialogs block waiting for a human, so these stub the underlying
# Tcl command (tk_getOpenFile, etc.) to capture the args it was actually
# invoked with and return a canned result - that proves the wrapper
# builds its Tcl call via tcl_invoke (no string interpolation), with
# options containing spaces/braces passed through intact, without ever
# popping up a real dialog. See sample/dialogs/dialogs_demo.rb for a
# manual, visual smoke test of the real thing.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestDialogs < Minitest::Test
  include TeekTestHelper

  tk_test "choose_open_file should pass options with spaces/braces safely and return the path" do
    app.tcl_eval(<<~TCL)
      proc tk_getOpenFile {args} {
        set ::last_call $args
        return {/tmp/some dir/a file {with braces}.png}
      }
    TCL

    result = app.choose_open_file(title: 'Pick a } file', initialdir: '/tmp/some dir')

    assert_equal '/tmp/some dir/a file {with braces}.png', result
    captured = tcl_flag_hash(app.tcl_eval('set ::last_call'))
    assert_equal({ '-title' => 'Pick a } file', '-initialdir' => '/tmp/some dir' }, captured)
  end

  tk_test "choose_open_file should return nil when the user cancels (empty Tk result)" do
    app.tcl_eval('proc tk_getOpenFile {args} { return {} }')

    assert_nil app.choose_open_file
  end

  tk_test "choose_open_file with multiple: true should split Tk's list result into an array" do
    app.tcl_eval(<<~TCL)
      proc tk_getOpenFile {args} {
        return {{/tmp/a file.png} /tmp/b.png}
      }
    TCL

    result = app.choose_open_file(multiple: true)

    assert_equal ['/tmp/a file.png', '/tmp/b.png'], result
  end

  tk_test "choose_open_file should build a correctly nested Tcl list for filetypes" do
    app.tcl_eval(<<~TCL)
      proc tk_getOpenFile {args} {
        set ::last_call $args
        return {}
      }
    TCL

    app.choose_open_file(filetypes: [['PNG Images', '.png'], ['All Files', '*']])

    captured = app.split_list(app.tcl_eval('set ::last_call'))
    filetypes_arg = captured[captured.index('-filetypes') + 1]
    entries = app.split_list(filetypes_arg)
    assert_equal ['PNG Images', '.png'], app.split_list(entries[0])
    assert_equal ['All Files', '*'], app.split_list(entries[1])
  end

  tk_test "choose_open_file filetypes should accept an array of extensions per entry" do
    app.tcl_eval(<<~TCL)
      proc tk_getOpenFile {args} {
        set ::last_call $args
        return {}
      }
    TCL

    app.choose_open_file(filetypes: [['Images', ['.png', '.jpg']]])

    captured = app.split_list(app.tcl_eval('set ::last_call'))
    filetypes_arg = captured[captured.index('-filetypes') + 1]
    entry = app.split_list(app.split_list(filetypes_arg)[0])
    assert_equal 'Images', entry[0]
    assert_equal ['.png', '.jpg'], app.split_list(entry[1])
  end

  tk_test "choose_save_file should pass options safely and return the path" do
    app.tcl_eval(<<~TCL)
      proc tk_getSaveFile {args} {
        set ::last_call $args
        return {/tmp/save dir/out.png}
      }
    TCL

    result = app.choose_save_file(title: 'Save As', initialfile: 'my file.png',
                                   defaultextension: '.png')

    assert_equal '/tmp/save dir/out.png', result
    captured = tcl_flag_hash(app.tcl_eval('set ::last_call'))
    assert_equal(
      { '-title' => 'Save As', '-initialfile' => 'my file.png', '-defaultextension' => '.png' },
      captured
    )
  end

  tk_test "choose_save_file should return nil when the user cancels" do
    app.tcl_eval('proc tk_getSaveFile {args} { return {} }')

    assert_nil app.choose_save_file
  end

  tk_test "message_box should pass options safely and return the pressed button as a symbol" do
    app.tcl_eval(<<~TCL)
      proc tk_messageBox {args} {
        set ::last_call $args
        return {yes}
      }
    TCL

    result = app.message_box(message: "Delete {this}?", title: 'Confirm', icon: :warning, type: :yesno)

    assert_equal :yes, result
    captured = tcl_flag_hash(app.tcl_eval('set ::last_call'))
    assert_equal(
      { '-message' => 'Delete {this}?', '-title' => 'Confirm', '-icon' => 'warning', '-type' => 'yesno' },
      captured
    )
  end

  tk_test "choose_color should pass options safely and return the chosen color" do
    app.tcl_eval(<<~TCL)
      proc tk_chooseColor {args} {
        set ::last_call $args
        return {#ff0080}
      }
    TCL

    result = app.choose_color(initial: '#ff0000', title: 'Pick a } color')

    assert_equal '#ff0080', result
    captured = tcl_flag_hash(app.tcl_eval('set ::last_call'))
    assert_equal({ '-initialcolor' => '#ff0000', '-title' => 'Pick a } color' }, captured)
  end

  tk_test "choose_color should return nil when the user cancels" do
    app.tcl_eval('proc tk_chooseColor {args} { return {} }')

    assert_nil app.choose_color
  end

  tk_test "choose_dir should pass options safely and return the chosen directory" do
    app.tcl_eval(<<~TCL)
      proc tk_chooseDirectory {args} {
        set ::last_call $args
        return {/tmp/some dir/with {braces}}
      }
    TCL

    result = app.choose_dir(title: 'Pick a } folder', initialdir: '/tmp/some dir')

    assert_equal '/tmp/some dir/with {braces}', result
    captured = tcl_flag_hash(app.tcl_eval('set ::last_call'))
    assert_equal({ '-title' => 'Pick a } folder', '-initialdir' => '/tmp/some dir' }, captured)
  end

  tk_test "choose_dir should return nil when the user cancels (empty Tk result)" do
    app.tcl_eval('proc tk_chooseDirectory {args} { return {} }')

    assert_nil app.choose_dir
  end

  tk_test "choose_dir's mustexist: should only appear on the wire when true (Tk's own default is false)" do
    app.tcl_eval(<<~TCL)
      proc tk_chooseDirectory {args} {
        set ::last_call $args
        return {}
      }
    TCL

    app.choose_dir
    refute_includes app.tcl_eval('set ::last_call'), '-mustexist'

    app.choose_dir(mustexist: true)
    captured = tcl_flag_hash(app.tcl_eval('set ::last_call'))
    assert_equal '1', captured['-mustexist']
  end

  tk_test "popup_menu should invoke tk_popup with the menu path and screen coordinates" do
    app.tcl_eval(<<~TCL)
      proc tk_popup {args} {
        set ::last_call $args
      }
    TCL
    menu = app.menu('.popup_test_menu')

    app.popup_menu(menu, x: 100, y: 200)

    captured = app.split_list(app.tcl_eval('set ::last_call'))
    assert_equal [menu.to_s, '100', '200'], captured
  end

  tk_test "popup_menu should pass an explicit active entry when given" do
    app.tcl_eval(<<~TCL)
      proc tk_popup {args} {
        set ::last_call $args
      }
    TCL
    menu = app.menu('.popup_test_menu2')

    app.popup_menu(menu, x: 10, y: 20, entry: 1)

    captured = app.split_list(app.tcl_eval('set ::last_call'))
    assert_equal [menu.to_s, '10', '20', '1'], captured
  end
end
