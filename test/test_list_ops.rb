# frozen_string_literal: true

# Tests for Teek.split_list and Teek.make_list module functions.
# These are pure Tcl list ops with no Tk/interpreter dependency.

require 'minitest/autorun'
require 'tcltklib'

class TestListOps < Minitest::Test

  # -- Teek.split_list ---------------------------------------------------

  def test_split_list_basic
    assert_equal %w[a b c], Teek.split_list("a b c")
  end

  def test_split_list_quoted
    assert_equal ["hello world", "foo", "bar baz"],
                 Teek.split_list('{hello world} foo {bar baz}')
  end

  def test_split_list_empty_string
    assert_equal [], Teek.split_list("")
  end

  def test_split_list_nil
    assert_equal [], Teek.split_list(nil)
  end

  def test_split_list_invalid
    assert_raises(Teek::TclError) { Teek.split_list('{"unclosed') }
  end

  # -- Teek.make_list ----------------------------------------------------

  def test_make_list_basic
    assert_equal "a b c", Teek.make_list("a", "b", "c")
  end

  def test_make_list_with_spaces
    result = Teek.make_list("hello world", "foo", "bar baz")
    assert_equal ["hello world", "foo", "bar baz"], Teek.split_list(result)
  end

  def test_make_list_empty
    assert_equal "", Teek.make_list
  end

  # -- make_list edge cases (crash resistance) ---------------------------

  def test_make_list_nil_arg
    assert_raises(TypeError) { Teek.make_list(nil) }
  end

  def test_make_list_integer_arg
    assert_raises(TypeError) { Teek.make_list(42) }
  end

  def test_make_list_symbol_arg
    assert_raises(TypeError) { Teek.make_list(:foo) }
  end

  def test_make_list_bad_arg_after_good
    # First arg valid, second bad — must not leak Tcl objects or crash
    assert_raises(TypeError) { Teek.make_list("good", 42) }
  end

  def test_make_list_null_bytes
    input = "hello\x00world"
    result = Teek.make_list(input)
    assert_equal [input], Teek.split_list(result)
  end

  def test_make_list_tcl_special_chars
    specials = ['{', '}', '{}', '[cmd]', '$var', 'back\\slash',
                '; dangerous', '"quoted"', '{unmatched', "\t\n"]
    specials.each do |s|
      parsed = Teek.split_list(Teek.make_list(s))
      assert_equal [s], parsed, "round-trip failed for #{s.inspect}"
    end
  end

  def test_make_list_empty_string_args
    result = Teek.make_list("", "", "")
    assert_equal ["", "", ""], Teek.split_list(result)
  end

  def test_make_list_many_args
    inputs = (1..1000).map { |i| "item_#{i}" }
    assert_equal inputs, Teek.split_list(Teek.make_list(*inputs))
  end

  def test_make_list_long_string
    long = "x" * 1_000_000
    assert_equal [long], Teek.split_list(Teek.make_list(long))
  end

  # -- Round-trip --------------------------------------------------------

  def test_round_trip
    inputs = ["hello world", "foo{bar}", 'back\\slash', "", "simple"]
    assert_equal inputs, Teek.split_list(Teek.make_list(*inputs))
  end
end
