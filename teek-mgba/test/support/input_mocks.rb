# frozen_string_literal: true

require 'set'

# Mock device for gamepad tests — responds to the same interface as
# SDL2::Gamepad (button?, closed?, guid, name).
class MockGamepad
  attr_reader :buttons_pressed

  def initialize(guid: 'abc-123', name: 'Test Pad')
    @guid = guid
    @name = name
    @buttons_pressed = Set.new
    @closed = false
  end

  def guid = @guid
  def name = @name
  def closed? = @closed
  def close! = @closed = true

  def button?(btn)
    @buttons_pressed.include?(btn)
  end
end

# Mock config that records set_mapping / set_dead_zone calls and
# returns configurable mapping data.
class MockInputConfig
  attr_reader :calls

  def initialize(keyboard_mappings: {}, gamepad_data: nil)
    @keyboard_mappings = keyboard_mappings
    @gamepad_data = gamepad_data || {
      'mappings' => { 'a' => 'x', 'b' => 'y' },
      'dead_zone' => 15,
    }
    @calls = []
  end

  def mappings(_guid)
    @keyboard_mappings
  end

  def gamepad(guid, name:)
    @calls << [:gamepad, guid, name]
    @gamepad_data
  end

  def set_mapping(guid, gba_btn, input)
    @calls << [:set_mapping, guid, gba_btn, input]
  end

  def set_dead_zone(guid, pct)
    @calls << [:set_dead_zone, guid, pct]
  end

  def reload!
    @calls << [:reload!]
  end
end
