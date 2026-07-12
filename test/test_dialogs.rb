# frozen_string_literal: true

# Tests for App's safe Tk dialog wrappers (choose_open_file,
# choose_save_file, message_box, choose_color, popup_menu).
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

  def test_choose_open_file_quotes_options_and_returns_the_path
    assert_tk_app("choose_open_file should pass options with spaces/braces safely and return the path") do
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
  end

  def test_choose_open_file_returns_nil_on_cancel
    assert_tk_app("choose_open_file should return nil when the user cancels (empty Tk result)") do
      app.tcl_eval('proc tk_getOpenFile {args} { return {} }')

      assert_nil app.choose_open_file
    end
  end

  def test_choose_open_file_multiple_returns_an_array
    assert_tk_app("choose_open_file with multiple: true should split Tk's list result into an array") do
      app.tcl_eval(<<~TCL)
        proc tk_getOpenFile {args} {
          return {{/tmp/a file.png} /tmp/b.png}
        }
      TCL

      result = app.choose_open_file(multiple: true)

      assert_equal ['/tmp/a file.png', '/tmp/b.png'], result
    end
  end

  def test_choose_open_file_filetypes_builds_a_properly_nested_list
    assert_tk_app("choose_open_file should build a correctly nested Tcl list for filetypes") do
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
  end

  def test_choose_open_file_filetypes_supports_multiple_extensions_per_entry
    assert_tk_app("choose_open_file filetypes should accept an array of extensions per entry") do
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
  end

  def test_choose_save_file_quotes_options_and_returns_the_path
    assert_tk_app("choose_save_file should pass options safely and return the path") do
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
  end

  def test_choose_save_file_returns_nil_on_cancel
    assert_tk_app("choose_save_file should return nil when the user cancels") do
      app.tcl_eval('proc tk_getSaveFile {args} { return {} }')

      assert_nil app.choose_save_file
    end
  end

  def test_message_box_quotes_options_and_returns_a_symbol
    assert_tk_app("message_box should pass options safely and return the pressed button as a symbol") do
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
  end

  def test_choose_color_quotes_options_and_returns_the_color
    assert_tk_app("choose_color should pass options safely and return the chosen color") do
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
  end

  def test_choose_color_returns_nil_on_cancel
    assert_tk_app("choose_color should return nil when the user cancels") do
      app.tcl_eval('proc tk_chooseColor {args} { return {} }')

      assert_nil app.choose_color
    end
  end

  def test_popup_menu_invokes_tk_popup_with_positional_coordinates
    assert_tk_app("popup_menu should invoke tk_popup with the menu path and screen coordinates") do
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
  end

  def test_popup_menu_passes_an_explicit_entry
    assert_tk_app("popup_menu should pass an explicit active entry when given") do
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
end
