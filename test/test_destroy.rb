# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestDestroy < Minitest::Test
  include TeekTestHelper

  tk_test "destroy should remove a widget" do
    app.command('ttk::button', '.btn', text: 'hi')
    assert_equal '1', app.tcl_eval('winfo exists .btn')

    app.destroy('.btn')
    assert_equal '0', app.tcl_eval('winfo exists .btn')
  end

  tk_test "destroy should remove widget and its children" do
    app.command('ttk::frame', '.f')
    app.command('ttk::button', '.f.b1', text: 'one')
    app.command('ttk::button', '.f.b2', text: 'two')

    app.destroy('.f')
    assert_equal '0', app.tcl_eval('winfo exists .f')
    assert_equal '0', app.tcl_eval('winfo exists .f.b1')
  end

  tk_test "destroy nonexistent widget should not raise" do
    # Tcl's destroy silently ignores nonexistent windows, so this should not raise
    app.destroy('.does_not_exist')
  end
end
