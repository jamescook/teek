# frozen_string_literal: true

require_relative 'test_helper'
require 'teek'

# support/fake_app.rb's FakeApp/FakeWindow stand in for Teek::App/
# Teek::Window in headless tests - Realizer/Handle only ever call a
# handful of methods on whichever app object they're given, so the fakes
# implement just those, not the real classes' full surface. What they DO
# implement needs to stay call-compatible with the real thing, or a
# headless test could keep passing against a contract production code no
# longer honors. RSpec has verifying doubles (instance_double) for
# exactly this; Minitest doesn't, so this hand-rolls the same idea as an
# ordinary failing test instead of a load-time check that would just
# blow up the whole suite with a raw exception.
class TestFakeAppContract < Minitest::Test
  FAKE_APP_METHODS = %i[command bind on_close popup_menu window].freeze
  FAKE_WINDOW_METHODS = %i[modal grab_release].freeze

  def test_fake_app_methods_are_signature_compatible_with_teek_app
    FAKE_APP_METHODS.each do |name|
      assert_signature_compatible(FakeApp.instance_method(name), Teek::App.instance_method(name), name)
    end
  end

  def test_fake_window_methods_are_signature_compatible_with_teek_window
    FAKE_WINDOW_METHODS.each do |name|
      assert_signature_compatible(FakeWindow.instance_method(name), Teek::Window.instance_method(name), name)
    end
  end

  private

  # Keyword names must match exactly (a renamed/added/removed kwarg is
  # the drift most likely to silently break a fake) - required vs
  # optional isn't distinguished, since the fake defaulting a kwarg the
  # real method requires is a harmless, common simplification for a stub.
  # Positional/rest SHAPE (ignoring req vs opt, same reasoning) must also
  # line up, since a dropped or added *args changes what call sites the
  # fake can stand in for. +&block+ presence is deliberately NOT compared
  # - a real method can accept a block via bare +yield+/+block_given?+
  # with no +&block+ param at all (see Teek::Window#modal), which
  # +Method#parameters+ has no way to see - only a fake DECLARING a block
  # param when the real method can't take one at all would be a genuine
  # mismatch, and that's not a failure mode worth the false positives
  # this check would otherwise raise on every yield-based real method.
  def assert_signature_compatible(fake_method, real_method, name)
    assert_equal keyword_names(real_method), keyword_names(fake_method),
      "FakeApp/FakeWindow##{name}'s keyword arguments have drifted from the real Teek method's"

    assert_equal positional_shape(real_method), positional_shape(fake_method),
      "FakeApp/FakeWindow##{name}'s positional/rest shape has drifted from the real Teek method's"
  end

  def keyword_names(method)
    method.parameters.select { |kind, _| %i[key keyreq].include?(kind) }.map { |_, param_name| param_name }.sort
  end

  def positional_shape(method)
    method.parameters.reject { |kind, _| %i[key keyreq keyrest block].include?(kind) }.map { |kind, _| kind }
  end
end
