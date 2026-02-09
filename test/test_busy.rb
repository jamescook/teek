# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestBusy < Minitest::Test
  include TeekTestHelper

  def test_busy_block
    assert_tk_app("busy sets and clears busy state", method(:app_busy_block))
  end

  def app_busy_block
    app.show
    app.update

    was_busy = false
    app.busy do
      result = app.tcl_eval('tk busy status .')
      was_busy = (result == '1')
    end

    after_busy = app.tcl_eval('tk busy status .')
    raise "expected busy during block, got not busy" unless was_busy
    raise "expected not busy after block, got busy" unless after_busy == '0'
  end

  def test_busy_block_returns_value
    assert_tk_app("busy returns block value", method(:app_busy_returns_value))
  end

  def app_busy_returns_value
    app.show
    app.update

    result = app.busy { 42 }
    raise "expected 42, got #{result}" unless result == 42
  end

  def test_busy_clears_on_exception
    assert_tk_app("busy clears on exception", method(:app_busy_clears_on_exception))
  end

  def app_busy_clears_on_exception
    app.show
    app.update

    begin
      app.busy { raise "boom" }
    rescue RuntimeError
      # expected
    end

    after = app.tcl_eval('tk busy status .')
    raise "expected not busy after exception, got busy" unless after == '0'
  end

  def test_busy_with_window
    assert_tk_app("busy works on specific window", method(:app_busy_with_window))
  end

  def app_busy_with_window
    app.show
    app.tcl_eval('toplevel .t')
    app.update

    was_busy = false
    app.busy(window: '.t') do
      result = app.tcl_eval('tk busy status .t')
      was_busy = (result == '1')
    end

    raise "expected .t busy during block" unless was_busy
    app.destroy('.t')
  end
end
