# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestWidget < Minitest::Test
  include TeekTestHelper

  def test_create_widget_returns_widget
    assert_tk_app("create_widget returns Widget") do
      btn = app.create_widget('ttk::button', text: 'Hi')
      assert_kind_of Teek::Widget, btn
      assert_equal app, btn.app
    end
  end

  def test_auto_naming
    assert_tk_app("auto-naming produces sequential paths") do
      b1 = app.create_widget('ttk::button', text: 'A')
      b2 = app.create_widget('ttk::button', text: 'B')
      lbl = app.create_widget(:label, text: 'C')
      assert_equal '.ttkbtn1', b1.path
      assert_equal '.ttkbtn2', b2.path
      assert_equal '.lbl1', lbl.path
    end
  end

  def test_auto_naming_with_parent
    assert_tk_app("auto-naming nests under parent") do
      frm = app.create_widget('ttk::frame')
      btn = app.create_widget('ttk::button', parent: frm, text: 'Hi')
      assert_equal '.ttkfrm1', frm.path
      assert_equal '.ttkfrm1.ttkbtn1', btn.path
    end
  end

  def test_explicit_path
    assert_tk_app("explicit path is used as-is") do
      frm = app.create_widget('ttk::frame', '.myframe')
      assert_equal '.myframe', frm.path
    end
  end

  def test_to_s
    assert_tk_app("to_s returns path") do
      btn = app.create_widget('ttk::button', text: 'Hi')
      assert_equal btn.path, btn.to_s
    end
  end

  def test_command_delegates
    assert_tk_app("command delegates to app") do
      btn = app.create_widget('ttk::button', text: 'Original')
      btn.command(:configure, text: 'Updated')
      assert_equal 'Updated', btn.command(:cget, '-text')
    end
  end

  def test_destroy_and_exist
    assert_tk_app("destroy and exist? work") do
      btn = app.create_widget('ttk::button', text: 'Hi')
      assert btn.exist?, "should exist after creation"
      btn.destroy
      refute btn.exist?, "should not exist after destroy"
    end
  end

  def test_interop_with_app_command
    assert_tk_app("widget works with app.command") do
      btn = app.create_widget('ttk::button', text: 'Hi')
      app.command(:pack, btn, pady: 10)
      assert_equal 'pack', app.tcl_eval("winfo manager #{btn}")
    end
  end

  def test_widget_tracking
    assert_tk_app("widget tracking works with create_widget") do
      btn = app.create_widget('ttk::button', text: 'Hi')
      app.update
      assert app.widgets[btn.path], "widget should be tracked"
      btn.destroy
      app.update
      refute app.widgets[btn.path], "widget should be untracked"
    end
  end

  def test_pack_returns_self
    assert_tk_app("pack returns self for chaining") do
      btn = app.create_widget('ttk::button', text: 'Hi')
      assert_same btn, btn.pack(pady: 10)
    end
  end

  def test_grid_returns_self
    assert_tk_app("grid returns self for chaining") do
      frm = app.create_widget('ttk::frame')
      frm.pack
      btn = app.create_widget('ttk::button', parent: frm, text: 'Hi')
      assert_same btn, btn.grid(row: 0, column: 0)
    end
  end

  def test_bind_and_unbind
    assert_tk_app("bind and unbind delegate to app") do
      btn = app.create_widget('ttk::button', text: 'Hi')
      btn.pack
      bound = false
      btn.bind('Enter') { bound = true }
      app.tcl_eval("event generate #{btn} <Enter>")
      app.update
      assert bound, "bind should have fired"
      btn.unbind('Enter')
      bound = false
      app.tcl_eval("event generate #{btn} <Enter>")
      app.update
      refute bound, "unbind should have cleared binding"
    end
  end

  def test_inspect
    assert_tk_app("inspect shows class and path") do
      btn = app.create_widget('ttk::button', text: 'Hi')
      assert_includes btn.inspect, btn.path
      assert_includes btn.inspect, 'Teek::Widget'
    end
  end

  def test_equality
    assert_tk_app("equality by path") do
      btn = app.create_widget('ttk::button', text: 'Hi')
      assert_equal btn, btn.path
      assert_equal btn, Teek::Widget.new(app, btn.path)
      assert_equal btn.path.hash, btn.hash
    end
  end
end
