# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestBusy < Minitest::Test
  include TeekTestHelper

  def test_busy_block
    assert_tk_app("busy sets and clears busy state") do
      app.show
      app.update

      was_busy = false
      app.busy do
        result = app.tcl_eval('tk busy status .')
        was_busy = (result == '1')
      end

      assert was_busy, "expected busy during block"
      assert_equal '0', app.tcl_eval('tk busy status .')
    end
  end

  def test_busy_block_returns_value
    assert_tk_app("busy returns block value") do
      app.show
      app.update

      assert_equal 42, app.busy { 42 }
    end
  end

  def test_busy_clears_on_exception
    assert_tk_app("busy clears on exception") do
      app.show
      app.update

      assert_raises(RuntimeError) { app.busy { raise "boom" } }
      assert_equal '0', app.tcl_eval('tk busy status .')
    end
  end

  def test_busy_with_window
    assert_tk_app("busy works on specific window") do
      app.show
      app.tcl_eval('toplevel .t')
      app.update

      was_busy = false
      app.busy(window: '.t') do
        result = app.tcl_eval('tk busy status .t')
        was_busy = (result == '1')
      end

      assert was_busy, "expected .t busy during block"
      app.destroy('.t')
    end
  end
end
