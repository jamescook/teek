# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/modal_stack'

# Pure stack-bookkeeping and callback-lifecycle tests, no Tk involved -
# ModalStack wraps Screens for the actual reveal/conceal, which is already
# covered (headlessly and against real Tk) by test_screens.rb/
# test_screens_realtk.rb. These focus on what's actually new here: when
# on_enter/on_exit/on_focus_change fire.
class TestModalStack < Minitest::Test
  FakeWindow = Struct.new(:shows, :hides) do
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

  FakeLazyWindow = Struct.new(:shows, :hides, :realized_flag, :realize_calls) do
    def initialize(shows = [], hides = [], realized_flag = false)
      super(shows, hides, realized_flag, [])
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

    def realized?
      realized_flag
    end

    def realize!(document)
      realize_calls << document
      self.realized_flag = true
    end
  end

  def test_starts_empty
    stack = Teek::UI::ModalStack.new(on_enter: ->(_) { }, on_exit: -> { })

    refute stack.active?
    assert_nil stack.current
    assert_equal 0, stack.size
  end

  def test_push_on_an_empty_stack_fires_on_enter_and_on_focus_change_and_shows_the_window
    enters = []
    focus_changes = []
    settings = FakeWindow.new
    stack = Teek::UI::ModalStack.new(
      on_enter: ->(name) { enters << name },
      on_exit: -> { },
      on_focus_change: ->(name) { focus_changes << name },
    )

    stack.push(:settings, settings)

    assert stack.active?
    assert_equal :settings, stack.current
    assert_equal 1, stack.size
    assert_equal [:settings], enters
    assert_equal [:settings], focus_changes
    assert_equal [true], settings.shows
  end

  def test_pushing_a_second_modal_does_not_fire_on_enter_again_but_hides_the_first_and_shows_the_second
    enters = []
    focus_changes = []
    settings = FakeWindow.new
    replay = FakeWindow.new
    stack = Teek::UI::ModalStack.new(
      on_enter: ->(name) { enters << name },
      on_exit: -> { },
      on_focus_change: ->(name) { focus_changes << name },
    )
    stack.push(:settings, settings)

    stack.push(:replay, replay)

    assert_equal :replay, stack.current
    assert_equal 2, stack.size
    assert_equal [:settings], enters, "on_enter should only fire on the empty -> non-empty transition"
    assert_equal [:settings, :replay], focus_changes
    assert_equal [true], settings.hides, "the previous top should be withdrawn, not dismissed"
    assert_equal [true], replay.shows
  end

  def test_pop_with_a_modal_remaining_reveals_it_and_fires_on_focus_change_not_on_exit
    exits = 0
    focus_changes = []
    settings = FakeWindow.new
    replay = FakeWindow.new
    stack = Teek::UI::ModalStack.new(
      on_enter: ->(_) { },
      on_exit: -> { exits += 1 },
      on_focus_change: ->(name) { focus_changes << name },
    )
    stack.push(:settings, settings)
    stack.push(:replay, replay)
    focus_changes.clear

    stack.pop

    assert_equal :settings, stack.current
    assert_equal 1, stack.size
    assert_equal [true], replay.hides
    assert_equal [true, true], settings.shows, "settings should be re-shown"
    assert_equal [:settings], focus_changes
    assert_equal 0, exits
  end

  def test_popping_the_last_modal_fires_on_exit_not_on_focus_change
    exits = 0
    focus_changes = []
    settings = FakeWindow.new
    stack = Teek::UI::ModalStack.new(
      on_enter: ->(_) { },
      on_exit: -> { exits += 1 },
      on_focus_change: ->(name) { focus_changes << name },
    )
    stack.push(:settings, settings)
    focus_changes.clear

    stack.pop

    refute stack.active?
    assert_nil stack.current
    assert_equal 0, stack.size
    assert_equal [true], settings.hides
    assert_equal 1, exits
    assert_equal [], focus_changes
  end

  def test_pop_on_an_empty_stack_is_a_safe_no_op
    exits = 0
    stack = Teek::UI::ModalStack.new(on_enter: ->(_) { }, on_exit: -> { exits += 1 })

    stack.pop

    refute stack.active?
    assert_equal 0, exits
  end

  def test_on_focus_change_is_optional
    settings = FakeWindow.new
    stack = Teek::UI::ModalStack.new(on_enter: ->(_) { }, on_exit: -> { })

    stack.push(:settings, settings)
    stack.pop

    assert_equal [true], settings.shows
    assert_equal [true], settings.hides
  end

  def test_document_is_forwarded_to_the_internal_screens_for_lazy_realize
    settings = FakeLazyWindow.new
    stack = Teek::UI::ModalStack.new(on_enter: ->(_) { }, on_exit: -> { }, document: :the_document)

    stack.push(:settings, settings)

    assert_equal [:the_document], settings.realize_calls
  end

  def test_pop_returns_the_popped_window
    settings = FakeWindow.new
    stack = Teek::UI::ModalStack.new(on_enter: ->(_) { }, on_exit: -> { })
    stack.push(:settings, settings)

    assert_same settings, stack.pop
  end

  def test_pop_on_an_empty_stack_returns_nil
    stack = Teek::UI::ModalStack.new(on_enter: ->(_) { }, on_exit: -> { })

    assert_nil stack.pop
  end

  def test_a_push_push_pop_pop_sequence_fires_on_enter_once_on_focus_change_thrice_on_exit_once
    enters = []
    exits = 0
    focus_changes = []
    settings = FakeWindow.new
    replay = FakeWindow.new
    stack = Teek::UI::ModalStack.new(
      on_enter: ->(name) { enters << name },
      on_exit: -> { exits += 1 },
      on_focus_change: ->(name) { focus_changes << name },
    )

    stack.push(:settings, settings)
    stack.push(:replay, replay)
    stack.pop
    stack.pop

    assert_equal [:settings], enters
    assert_equal [:settings, :replay, :settings], focus_changes
    assert_equal 1, exits
    refute stack.active?
  end
end
