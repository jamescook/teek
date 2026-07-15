# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

class TestMenuRealize < Minitest::Test
  include TeekTestHelper

  def test_menu_bar_attaches_to_the_root_window
    assert_tk_app("a top-level menu_bar should attach via -menu to the root window") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Menu Realize Test') do |ui|
        ui.menu_bar(:mb) { |mb| mb.menu(label: 'File') }
      end
      session.run_async
      session.app.update

      assert_equal session[:mb].path, session.app.tcl_eval('. cget -menu')

      session.app.destroy
    end
  end

  def test_menu_bar_attaches_to_a_ui_window_not_just_the_root
    assert_tk_app("a menu_bar declared inside ui.window should attach to that window, not the root") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Menu Realize Test') do |ui|
        ui.window(:settings) { |w| w.menu_bar(:mb) { |mb| mb.menu(label: 'File') } }
      end
      session.run_async
      session.app.update

      settings_path = session[:settings].path
      assert_equal session[:mb].path, session.app.tcl_eval("#{settings_path} cget -menu")
      refute_equal session[:mb].path, session.app.tcl_eval('. cget -menu'),
        "the root window should not also pick up the settings window's menu bar"

      session.app.destroy
    end
  end

  def test_nested_menu_realizes_as_a_cascade_under_its_parents_path
    assert_tk_app("a nested .menu should realize as a real menu widget, added as a cascade entry") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Menu Realize Test') do |ui|
        ui.menu_bar(:mb) { |mb| mb.menu(:file, label: 'File') }
      end
      session.run_async
      session.app.update

      mb_path = session[:mb].path
      file_path = session[:file].path
      assert session.app.winfo.exists?(file_path)
      assert file_path.start_with?("#{mb_path}."),
        "a submenu's path (#{file_path}) should be nested under its parent menu's path (#{mb_path}) - Tk requires it"

      assert_equal 'cascade', session.app.tcl_eval("#{mb_path} type 0")
      assert_equal 'File', session.app.command(mb_path, :entrycget, 0, '-label')
      assert_equal file_path, session.app.command(mb_path, :entrycget, 0, '-menu')

      session.app.destroy
    end
  end

  def test_item_fires_its_block_on_invoke
    assert_tk_app("a menu item's block should fire like any other command entry") do
      require 'teek/ui'

      fired = false
      session = Teek::UI.app(title: 'Menu Realize Test') do |ui|
        ui.menu_bar { |mb| mb.menu(:file, label: 'File') { |f| f.item(label: 'Open') { fired = true } } }
      end
      session.run_async
      session.app.update

      session.app.tcl_eval("#{session[:file].path} invoke 0")

      assert fired, "the item's block did not fire"

      session.app.destroy
    end
  end

  def test_named_item_is_addressable_via_ui_name_and_supports_enable_disable_configure
    assert_tk_app("a named item should be addressable via ui[:name] and support .enable/.disable/.configure") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Menu Realize Test') do |ui|
        ui.menu_bar do |mb|
          mb.menu(:file, label: 'File') do |f|
            f.item(label: 'New') { }
            f.item(:quick_load, label: 'Quick Load') { }
          end
        end
      end
      session.run_async
      session.app.update

      file_path = session[:file].path
      item = session[:quick_load]

      assert_equal 'normal', session.app.command(file_path, :entrycget, 1, '-state')

      item.disable
      assert_equal 'disabled', session.app.command(file_path, :entrycget, 1, '-state')

      item.enable
      assert_equal 'normal', session.app.command(file_path, :entrycget, 1, '-state')

      item.configure(label: 'Load Recent Save')
      assert_equal 'Load Recent Save', session.app.command(file_path, :entrycget, 1, '-label')

      session.app.destroy
    end
  end

  def test_named_item_stays_correctly_addressed_after_an_earlier_sibling_is_removed
    assert_tk_app("addressing a named item should stay correct even after an earlier sibling entry is removed") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Menu Realize Test') do |ui|
        ui.menu_bar do |mb|
          mb.menu(:file, label: 'File') do |f|
            f.item(label: 'New') { }
            f.item(:quick_load, label: 'Quick Load') { }
          end
        end
      end
      session.run_async
      session.app.update

      file_path = session[:file].path
      # Removing "New" shifts Quick Load's live index from 1 down to 0 -
      # Tk itself renumbers around the delete; addressing by name should
      # still land on the right entry with no stale cached index.
      session.app.command(file_path, :delete, 0)

      session[:quick_load].disable

      assert_equal 'disabled', session.app.command(file_path, :entrycget, 0, '-state')

      session.app.destroy
    end
  end

  def test_named_item_virtual_path_is_marked_and_rejected_by_a_raw_tk_call
    assert_tk_app("a named item's .path should be marked past the real Tk boundary, and rejected if used raw") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Menu Realize Test') do |ui|
        ui.menu_bar { |mb| mb.menu(:file, label: 'File') { |f| f.item(:quick_load, label: 'Quick Load') { } } }
      end
      session.run_async
      session.app.update

      file_path = session[:file].path
      virtual_path = session[:quick_load].path
      assert_equal "#{file_path}!quick_load", virtual_path

      error = assert_raises(Teek::TclError) { session.app.tcl_eval("#{virtual_path} entrycget 0 -label") }
      assert_match(/invalid command name/i, error.message)

      session.app.destroy
    end
  end

  def test_separator_realizes_as_a_real_separator_entry
    assert_tk_app("ui.separator should realize as a real Tk separator entry") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Menu Realize Test') do |ui|
        ui.menu_bar { |mb| mb.menu(:file, label: 'File') { |f| f.item(label: 'Open') { }; f.separator } }
      end
      session.run_async
      session.app.update

      assert_equal 'separator', session.app.tcl_eval("#{session[:file].path} type 1")

      session.app.destroy
    end
  end

  def test_checkbox_entry_stays_in_sync_with_its_bound_var
    assert_tk_app("a menu checkbox entry bound to a var should toggle that var on invoke") do
      require 'teek/ui'

      wrap = nil
      session = Teek::UI.app(title: 'Menu Realize Test') do |ui|
        wrap = ui.var(false)
        ui.menu_bar { |mb| mb.menu(:edit, label: 'Edit') { |e| e.checkbox(label: 'Word Wrap', bind: wrap) } }
      end
      session.run_async
      session.app.update

      assert_equal false, wrap.value

      session.app.tcl_eval("#{session[:edit].path} invoke 0")

      assert_equal true, wrap.value, "invoking the checkbutton entry should flip the bound var"

      session.app.destroy
    end
  end

  def test_radio_entries_share_one_var_and_set_its_own_value_on_invoke
    assert_tk_app("menu radio entries bound to the same var should set it to their own value on invoke") do
      require 'teek/ui'

      size = nil
      session = Teek::UI.app(title: 'Menu Realize Test') do |ui|
        size = ui.var('small')
        ui.menu_bar do |mb|
          mb.menu(:edit, label: 'Edit') do |e|
            e.radio(label: 'Small', bind: size, value: 'small')
            e.radio(label: 'Large', bind: size, value: 'large')
          end
        end
      end
      session.run_async
      session.app.update

      session.app.tcl_eval("#{session[:edit].path} invoke 1")

      assert_equal 'large', size.value

      session.app.destroy
    end
  end

  def test_rebuilding_a_menu_does_not_leak_entry_callbacks
    assert_tk_app("rebuilding a context menu's contents on every right-click should not accumulate entry callbacks") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Menu Realize Test') { |ui| ui.panel(:host) }
      session.run_async
      session.app.update
      baseline = session.app.interp.callback_ids.length

      ctx = nil
      5.times do
        session.app.destroy(ctx.path) if ctx
        session.add(:host) { |a| ctx = a.context_menu { |m| m.item(label: 'Delete') { }; m.item(label: 'Rename') { } } }
      end
      session.app.destroy(ctx.path)

      assert_equal baseline, session.app.interp.callback_ids.length,
        "rebuilding the context menu repeatedly should not accumulate callbacks"

      session.app.destroy
    end
  end

  def test_context_menu_pops_up_at_the_right_clicked_widgets_root_coordinates
    assert_tk_app("a widget wired via on_right_click(context_menu) should tk_popup the right menu at the click's screen coordinates") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Menu Realize Test') do |ui|
        ctx = ui.context_menu(:ctx) { |m| m.item(label: 'Delete') { } }
        ui.canvas(:board).on_right_click(ctx)
      end
      session.run_async
      session.app.update

      session.app.tcl_eval(<<~TCL)
        proc tk_popup {args} {
          set ::last_popup_call $args
        }
      TCL

      session.app.tcl_eval("event generate #{session[:board].path} <Button-3> -rootx 123 -rooty 456")

      captured = session.app.split_list(session.app.tcl_eval('set ::last_popup_call'))
      assert_equal [session[:ctx].path, '123', '456'], captured

      session.app.destroy
    end
  end

  def test_context_menu_declared_standalone_does_not_auto_attach_anywhere
    assert_tk_app("a context_menu should exist as a real widget but never auto-attach via -menu") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Menu Realize Test') { |ui| ui.context_menu(:ctx) { |m| m.item(label: 'Delete') { } } }
      session.run_async
      session.app.update

      assert session.app.winfo.exists?(session[:ctx].path)
      assert_equal '', session.app.tcl_eval('. cget -menu')

      session.app.destroy
    end
  end
end
