# frozen_string_literal: true

# Tests for Teek.tcl_to_bool and Teek.bool_to_tcl.
# Pure Tcl value conversion — no Tk window needed, but runs through
# assert_tk_app for consistent test infrastructure and coverage.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestBoolHelpers < Minitest::Test
  include TeekTestHelper

  # -- Teek.tcl_to_bool --------------------------------------------------

  tk_test "tcl_to_bool true variants" do
    %w[1 true TRUE True yes YES Yes on ON On].each do |s|
      assert_equal true, Teek.tcl_to_bool(s), "expected true for #{s.inspect}"
    end
  end

  tk_test "tcl_to_bool false variants" do
    %w[0 false FALSE False no NO No off OFF Off].each do |s|
      assert_equal false, Teek.tcl_to_bool(s), "expected false for #{s.inspect}"
    end
  end

  tk_test "tcl_to_bool numeric nonzero" do
    %w[2 -1 42 3.14].each do |s|
      assert_equal true, Teek.tcl_to_bool(s), "expected true for numeric #{s.inspect}"
    end
  end

  tk_test "tcl_to_bool numeric zero" do
    assert_equal false, Teek.tcl_to_bool("0")
    assert_equal false, Teek.tcl_to_bool("0.0")
  end

  tk_test "tcl_to_bool invalid raises TclError" do
    assert_raises(Teek::TclError) { Teek.tcl_to_bool("maybe") }
    assert_raises(Teek::TclError) { Teek.tcl_to_bool("") }
    assert_raises(Teek::TclError) { Teek.tcl_to_bool("yep") }
  end

  tk_test "tcl_to_bool non-string raises TypeError" do
    assert_raises(TypeError) { Teek.tcl_to_bool(nil) }
    assert_raises(TypeError) { Teek.tcl_to_bool(1) }
  end

  # -- Teek.bool_to_tcl --------------------------------------------------

  tk_test "bool_to_tcl truthy values" do
    assert_equal "1", Teek.bool_to_tcl(true)
    assert_equal "1", Teek.bool_to_tcl(1)
    assert_equal "1", Teek.bool_to_tcl("anything")
    assert_equal "1", Teek.bool_to_tcl(:sym)
  end

  tk_test "bool_to_tcl falsy values" do
    assert_equal "0", Teek.bool_to_tcl(false)
    assert_equal "0", Teek.bool_to_tcl(nil)
  end

  # -- Round-trip ---------------------------------------------------------

  tk_test "bool round-trip" do
    assert_equal true,  Teek.tcl_to_bool(Teek.bool_to_tcl(true))
    assert_equal false, Teek.tcl_to_bool(Teek.bool_to_tcl(false))
    assert_equal false, Teek.tcl_to_bool(Teek.bool_to_tcl(nil))
  end
end
