# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Realize-phase introspection: Session#find_by_path (reverse path->node
# lookup) and Handle#options (a live options dump straight from Tk). Both
# need a real interpreter to mean anything - a raw Tk path only exists
# once something's actually realized, and #options parses Tk's own
# `configure` return value, so these live in their own suite rather than
# a headless one. Handle#events (the third piece of this same bead) is
# pure Ruby with no Tk involved and is covered in test_handle.rb instead.
class TestWidgetIntrospection < Minitest::Test
  include TeekTestHelper

  tk_test "find_by_path should raise before realize, matching every other realize-only diagnostic" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Widget Introspection Test')

    assert_raises(Teek::UI::NotRealizedError) { session.find_by_path('.go') }
  end

  tk_test "find_by_path should return nil, not raise, for a path nothing was realized at" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Widget Introspection Test') { |ui| ui.button(:go, text: 'Go') }
    session.run_async

    assert_nil session.find_by_path('.nope')

    session.app.destroy
  end

  tk_test "find_by_path should resolve a real Tk path back to the same node ui[:name] would find" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Widget Introspection Test') { |ui| ui.button(:go, text: 'Go') }
    session.run_async

    found = session.find_by_path(session[:go].path)

    refute_nil found
    assert_equal :go, found.name
    assert_equal :button, found.type

    session.app.destroy
  end

  tk_test "find_by_path should see a widget added dynamically via session.add, not just the initial build" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Widget Introspection Test') { |ui| ui.column(:list) }
    session.run_async

    session.add(:list) { |a| a.button(:item1, text: 'Item 1') }

    found = session.find_by_path(session[:item1].path)

    refute_nil found
    assert_equal :item1, found.name

    session.app.destroy
  end

  tk_test "options should raise before realize, matching #configure" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Widget Introspection Test') { |ui| ui.button(:go, text: 'Go') }

    assert_raises(Teek::UI::NotRealizedError) { session[:go].options }
  end

  tk_test "options should reflect an option set at build time" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Widget Introspection Test') { |ui| ui.button(:go, text: 'Go') }
    session.run_async

    assert_equal 'Go', session[:go].options[:text]

    session.app.destroy
  end

  tk_test "options should reflect the CURRENT value, not just what the widget was built with" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Widget Introspection Test') { |ui| ui.button(:go, text: 'Go') }
    session.run_async

    session[:go].configure(text: 'Stop')

    assert_equal 'Stop', session[:go].options[:text]

    session.app.destroy
  end

  tk_test "options should work through MenuEntryAddressing too, not just ordinary widgets" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Widget Introspection Test') do |ui|
      ui.menu_bar { |mb| mb.menu(:file, label: 'File') { |f| f.item(:open, label: 'Open') { } } }
    end
    session.run_async

    assert_equal 'Open', session[:open].options[:label]

    session.app.destroy
  end
end
