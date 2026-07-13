# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/screens'

# Pure stack-bookkeeping tests, no Tk involved - Screens' reveal/conceal
# logic (pack/pack-forget for a panel, show/hide for a window) is exercised
# against real Tk widgets in test_screens_realtk.rb instead.
class TestScreens < Minitest::Test
  FakeApp = Struct.new(:calls) do
    def initialize(calls = [])
      super
    end

    def command(*args, **kwargs)
      calls << [args, kwargs]
    end
  end

  FakePanelScreen = Struct.new(:app, :path) do
    def type
      :panel
    end
  end

  FakeWindowScreen = Struct.new(:shows, :hides) do
    def initialize(shows = [], hides = [])
      super
    end

    def type
      :window
    end

    def show
      shows << true
    end

    def hide
      hides << true
    end
  end

  def test_starts_empty
    screens = Teek::UI::Screens.new

    refute screens.active?
    assert_nil screens.current
    assert_nil screens.current_screen
    assert_equal 0, screens.size
  end

  def test_push_activates_and_tracks_current
    screens = Teek::UI::Screens.new
    picker = FakePanelScreen.new(FakeApp.new, '.picker')

    screens.push(:picker, picker)

    assert screens.active?
    assert_equal :picker, screens.current
    assert_same picker, screens.current_screen
    assert_equal 1, screens.size
  end

  def test_push_reveals_a_panel_screen_by_packing_it_to_fill_its_parent
    screens = Teek::UI::Screens.new
    app = FakeApp.new
    picker = FakePanelScreen.new(app, '.picker')

    screens.push(:picker, picker)

    assert_equal [[[:pack, '.picker'], { fill: :both, expand: 1 }]], app.calls
  end

  def test_push_reveals_a_window_screen_via_show
    screens = Teek::UI::Screens.new
    settings = FakeWindowScreen.new

    screens.push(:settings, settings)

    assert_equal [true], settings.shows
    assert_equal [], settings.hides
  end

  def test_pushing_a_second_screen_conceals_the_first
    screens = Teek::UI::Screens.new
    app = FakeApp.new
    picker = FakePanelScreen.new(app, '.picker')
    emulator = FakePanelScreen.new(app, '.emulator')

    screens.push(:picker, picker)
    screens.push(:emulator, emulator)

    assert_equal :emulator, screens.current
    assert_equal 2, screens.size
    assert_equal [
      [[:pack, '.picker'], { fill: :both, expand: 1 }],
      [[:pack, :forget, '.picker'], {}],
      [[:pack, '.emulator'], { fill: :both, expand: 1 }],
    ], app.calls
  end

  def test_pop_conceals_the_current_and_reveals_the_one_underneath
    screens = Teek::UI::Screens.new
    app = FakeApp.new
    picker = FakePanelScreen.new(app, '.picker')
    emulator = FakePanelScreen.new(app, '.emulator')
    screens.push(:picker, picker)
    screens.push(:emulator, emulator)
    app.calls.clear

    screens.pop

    assert_equal :picker, screens.current
    assert_equal 1, screens.size
    assert_equal [
      [[:pack, :forget, '.emulator'], {}],
      [[:pack, '.picker'], { fill: :both, expand: 1 }],
    ], app.calls
  end

  def test_pop_on_the_last_screen_leaves_the_stack_inactive
    screens = Teek::UI::Screens.new
    picker = FakePanelScreen.new(FakeApp.new, '.picker')
    screens.push(:picker, picker)

    screens.pop

    refute screens.active?
    assert_nil screens.current
    assert_equal 0, screens.size
  end

  def test_pop_on_an_empty_stack_is_a_safe_no_op
    screens = Teek::UI::Screens.new

    screens.pop

    refute screens.active?
  end

  def test_replace_current_swaps_the_screen_but_keeps_the_name_and_depth
    screens = Teek::UI::Screens.new
    app = FakeApp.new
    picker = FakePanelScreen.new(app, '.picker')
    other_picker = FakePanelScreen.new(app, '.other_picker')
    screens.push(:picker, picker)
    app.calls.clear

    screens.replace_current(other_picker)

    assert_equal :picker, screens.current
    assert_same other_picker, screens.current_screen
    assert_equal 1, screens.size
    assert_equal [
      [[:pack, :forget, '.picker'], {}],
      [[:pack, '.other_picker'], { fill: :both, expand: 1 }],
    ], app.calls
  end

  def test_replace_current_on_an_empty_stack_is_a_safe_no_op
    screens = Teek::UI::Screens.new
    app = FakeApp.new
    picker = FakePanelScreen.new(app, '.picker')

    screens.replace_current(picker)

    refute screens.active?
    assert_equal [], app.calls
  end

  def test_a_three_deep_push_pop_push_sequence_restores_the_correct_screen_at_each_step
    screens = Teek::UI::Screens.new
    app = FakeApp.new
    picker = FakePanelScreen.new(app, '.picker')
    emulator = FakePanelScreen.new(app, '.emulator')
    settings = FakePanelScreen.new(app, '.settings')

    screens.push(:picker, picker)
    assert_equal :picker, screens.current
    assert_equal 1, screens.size

    screens.push(:emulator, emulator)
    assert_equal :emulator, screens.current
    assert_equal 2, screens.size

    screens.push(:settings, settings)
    assert_equal :settings, screens.current
    assert_equal 3, screens.size

    screens.pop
    assert_equal :emulator, screens.current
    assert_equal 2, screens.size

    screens.pop
    assert_equal :picker, screens.current
    assert_equal 1, screens.size

    screens.push(:settings, settings)
    assert_equal :settings, screens.current
    assert_equal 2, screens.size
  end
end
