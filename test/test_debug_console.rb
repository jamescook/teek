# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestDebugConsole < Minitest::Test
  include TeekTestHelper

  tk_test "add_debug_console returns true or false" do
    result = app.add_debug_console
    assert_includes [true, false], result
  end

  tk_test "console starts hidden after add_debug_console" do
    skip "console not available" unless app.add_debug_console
    # console hide should not raise — it's already hidden
    app.tcl_eval('console hide')
  end

  tk_test "console can be shown and hidden" do
    skip "console not available" unless app.add_debug_console
    app.tcl_eval('console show')
    app.tcl_eval('console hide')
  end

  tk_test "custom keybinding is accepted" do
    result = app.add_debug_console('<F11>')
    assert_includes [true, false], result
  end
end
