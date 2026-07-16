# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/event_bus'
require 'teek/ui/session'

# In-process publish/subscribe for decoupled app events - not Tk events,
# complementary to on_click/on_key (see Handle). Headless: no Tk/interpreter
# involved at all, pure Ruby object messaging.
class TestEventBus < Minitest::Test
  def test_on_and_emit
    bus = Teek::UI::EventBus.new
    received = nil

    bus.on(:ping) { |val| received = val }
    bus.emit(:ping, 42)

    assert_equal 42, received
  end

  def test_emit_with_no_subscribers_is_a_no_op
    bus = Teek::UI::EventBus.new

    bus.emit(:ghost, 1, 2, 3) # should not raise
  end

  def test_multiple_subscribers_all_fire_in_subscription_order
    bus = Teek::UI::EventBus.new
    results = []

    bus.on(:tick) { |v| results << "a:#{v}" }
    bus.on(:tick) { |v| results << "b:#{v}" }
    bus.emit(:tick, 7)

    assert_equal ['a:7', 'b:7'], results
  end

  def test_different_events_are_independent
    bus = Teek::UI::EventBus.new
    a = nil
    b = nil

    bus.on(:foo) { |v| a = v }
    bus.on(:bar) { |v| b = v }
    bus.emit(:foo, 1)

    assert_equal 1, a
    assert_nil b
  end

  def test_emit_forwards_multiple_positional_args
    bus = Teek::UI::EventBus.new
    received = nil

    bus.on(:multi) { |x, y| received = [x, y] }
    bus.emit(:multi, :a, :b)

    assert_equal [:a, :b], received
  end

  def test_emit_forwards_keyword_args
    bus = Teek::UI::EventBus.new
    received = nil

    bus.on(:kw) { |name:, val:| received = { name: name, val: val } }
    bus.emit(:kw, name: 'scale', val: 3)

    assert_equal({ name: 'scale', val: 3 }, received)
  end

  def test_off_removes_a_specific_subscriber
    bus = Teek::UI::EventBus.new
    received = []

    block = bus.on(:evt) { |v| received << v }
    bus.emit(:evt, 1)
    bus.off(:evt, block)
    bus.emit(:evt, 2)

    assert_equal [1], received
  end

  def test_off_only_removes_the_given_subscriber_not_others_on_the_same_event
    bus = Teek::UI::EventBus.new
    received = []

    keep = bus.on(:evt) { |v| received << "keep:#{v}" }
    drop = bus.on(:evt) { |v| received << "drop:#{v}" }
    bus.off(:evt, drop)
    bus.emit(:evt, 1)

    assert_equal ['keep:1'], received
    refute_nil keep
  end

  def test_on_returns_the_block_for_a_later_off
    bus = Teek::UI::EventBus.new

    block = bus.on(:x) { }

    assert_instance_of Proc, block
  end

  def test_two_independent_buses_do_not_see_each_others_events
    bus_a = Teek::UI::EventBus.new
    bus_b = Teek::UI::EventBus.new
    received_a = nil
    received_b = nil

    bus_a.on(:shared_name) { |v| received_a = v }
    bus_b.on(:shared_name) { |v| received_b = v }
    bus_a.emit(:shared_name, 'from a')

    assert_equal 'from a', received_a
    assert_nil received_b, "bus_b should never see bus_a's emit"
  end
end

# Session#on/#emit/#off delegate to one EventBus per session - app-scoped,
# not a global singleton, so two Teek::UI.app instances in the same
# process never see each other's events. Headless: works before realize,
# no Tk/interpreter needed at all.
class TestSessionEventBus < Minitest::Test
  def build_session
    Teek::UI::Session.new(title: 'Event Bus Test')
  end

  def test_on_and_emit_work_before_realize
    session = build_session
    received = nil

    session.on(:item_selected) { |id| received = id }
    session.emit(:item_selected, 42)

    assert_equal 42, received
  end

  def test_off_removes_a_specific_subscriber
    session = build_session
    received = []

    block = session.on(:evt) { |v| received << v }
    session.emit(:evt, 1)
    session.off(:evt, block)
    session.emit(:evt, 2)

    assert_equal [1], received
  end

  def test_two_independent_sessions_do_not_see_each_others_events
    session_a = build_session
    session_b = build_session
    received_a = nil
    received_b = nil

    session_a.on(:theme_changed) { |v| received_a = v }
    session_b.on(:theme_changed) { |v| received_b = v }
    session_a.emit(:theme_changed, 'dark')

    assert_equal 'dark', received_a
    assert_nil received_b, "session_b should never see session_a's emit"
  end
end
