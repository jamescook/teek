# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/node'
require 'teek/ui/handle'

class TestHandle < Minitest::Test
  FakeApp = Struct.new(:calls, :binds, :on_closes) do
    def initialize(calls = [], binds = [], on_closes = [])
      super
    end

    def command(*args, **kwargs)
      calls << [args, kwargs]
    end

    def bind(path, event, *subs, &block)
      binds << { path: path, event: event, subs: subs, block: block }
    end

    def on_close(window:, &block)
      on_closes << { window: window, block: block }
    end
  end

  def test_path_raises_before_realize
    node = Teek::UI::Node.new(type: :button, name: :save)
    handle = Teek::UI::Handle.new(node)

    error = assert_raises(Teek::UI::NotRealizedError) { handle.path }
    assert_match(/not realized/i, error.message)
  end

  def test_configure_raises_before_realize
    node = Teek::UI::Node.new(type: :button, name: :save)
    handle = Teek::UI::Handle.new(node)

    assert_raises(Teek::UI::NotRealizedError) { handle.configure(text: 'Go') }
  end

  def test_path_returns_the_real_path_once_realized
    node = Teek::UI::Node.new(type: :button, name: :save)
    node.realized = Teek::UI::RealizedNode.new(app: FakeApp.new([]), path: '.win.save')
    handle = Teek::UI::Handle.new(node)

    assert_equal '.win.save', handle.path
  end

  def test_configure_delegates_to_the_realized_apps_command_once_realized
    app = FakeApp.new([])
    node = Teek::UI::Node.new(type: :button, name: :save)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: '.win.save')
    handle = Teek::UI::Handle.new(node)

    handle.configure(text: 'Go', width: 10)

    assert_equal [[['.win.save', :configure], { text: 'Go', width: 10 }]], app.calls
  end

  def test_type_and_name_reflect_the_underlying_node_at_any_phase
    node = Teek::UI::Node.new(type: :button, name: :save)
    handle = Teek::UI::Handle.new(node)

    assert_equal :button, handle.type
    assert_equal :save, handle.name
  end

  def test_on_click_queues_an_event_binding_before_realize
    node = Teek::UI::Node.new(type: :button, name: :go)
    handle = Teek::UI::Handle.new(node)
    clicked = -> { }

    result = handle.on_click(&clicked)

    assert_same handle, result, "on_click should return self for chaining"
    assert_equal 1, node.events.length
    binding = node.events.first
    assert_equal '<Button-1>', binding.event
    assert_equal clicked, binding.handler
    assert_nil binding.target
  end

  def test_on_click_wires_immediately_once_already_realized
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :go)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: '.win.go')
    handle = Teek::UI::Handle.new(node)

    handle.on_click { }

    assert_equal [], node.events, "should wire immediately, not queue, once realized"
    assert_equal 1, app.binds.length
    assert_equal '.win.go', app.binds.first[:path]
    assert_equal '<Button-1>', app.binds.first[:event]
  end

  def test_on_key_friendly_symbol_queues_the_resolved_pattern
    node = Teek::UI::Node.new(type: :text_box, name: :query)
    handle = Teek::UI::Handle.new(node)

    handle.on_key(:enter) { }

    assert_equal ['<Return>'], node.events.map(&:event)
  end

  def test_on_key_modifier_string_queues_the_resolved_pattern
    node = Teek::UI::Node.new(type: :text_box, name: :query)
    handle = Teek::UI::Handle.new(node)

    handle.on_key('Ctrl-s') { }

    assert_equal ['<Control-s>'], node.events.map(&:event)
  end

  def test_on_drag_queues_with_x_y_subs
    node = Teek::UI::Node.new(type: :panel, name: :area)
    handle = Teek::UI::Handle.new(node)

    handle.on_drag { |_x, _y| }

    binding = node.events.first
    assert_equal '<B1-Motion>', binding.event
    assert_equal %i[x y], binding.subs
  end

  def test_on_right_click_queues_all_platform_variants
    node = Teek::UI::Node.new(type: :button, name: :go)
    handle = Teek::UI::Handle.new(node)

    handle.on_right_click { }

    assert_equal ['<Button-2>', '<Button-3>', '<Control-Button-1>'], node.events.map(&:event)
  end

  def test_on_close_queues_the_block_on_a_window_node_before_realize
    node = Teek::UI::Node.new(type: :window, name: :settings)
    handle = Teek::UI::Handle.new(node)
    closer = -> { }

    result = handle.on_close(&closer)

    assert_same handle, result, "on_close should return self for chaining"
    assert_equal closer, node.opts[:on_close]
  end

  def test_on_close_wires_immediately_once_already_realized
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :window, name: :settings)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: '.settings')
    handle = Teek::UI::Handle.new(node)

    handle.on_close { }

    assert_nil node.opts[:on_close], "should wire immediately, not queue, once realized"
    assert_equal 1, app.on_closes.length
    assert_equal '.settings', app.on_closes.first[:window]
  end

  def test_on_close_raises_on_a_non_window_node
    node = Teek::UI::Node.new(type: :button, name: :go)
    handle = Teek::UI::Handle.new(node)

    error = assert_raises(ArgumentError) { handle.on_close { } }
    assert_match(/window/i, error.message)
  end
end
