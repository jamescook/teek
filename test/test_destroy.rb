# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestDestroy < Minitest::Test
  include TeekTestHelper

  def test_destroy_removes_widget
    assert_tk_app("destroy should remove a widget", method(:app_destroy_widget))
  end

  def app_destroy_widget
    app.command('ttk::button', '.btn', text: 'hi')
    raise ".btn should exist" unless app.tcl_eval('winfo exists .btn') == '1'

    app.destroy('.btn')
    raise ".btn should not exist after destroy" unless app.tcl_eval('winfo exists .btn') == '0'
  end

  def test_destroy_removes_children
    assert_tk_app("destroy should remove widget and its children", method(:app_destroy_children))
  end

  def app_destroy_children
    app.command('ttk::frame', '.f')
    app.command('ttk::button', '.f.b1', text: 'one')
    app.command('ttk::button', '.f.b2', text: 'two')

    app.destroy('.f')
    raise ".f should not exist" unless app.tcl_eval('winfo exists .f') == '0'
    raise ".f.b1 should not exist" unless app.tcl_eval('winfo exists .f.b1') == '0'
  end

  def test_destroy_nonexistent_raises
    assert_tk_app("destroy nonexistent widget should raise", method(:app_destroy_nonexistent))
  end

  def app_destroy_nonexistent
    # Tcl's destroy silently ignores nonexistent windows, so this should not raise
    app.destroy('.does_not_exist')
  end
end
