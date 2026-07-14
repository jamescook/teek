# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/node'
require 'teek/ui/handle'

class TestHandle < Minitest::Test
  FakeWindow = Struct.new(:path, :modal_calls, :grab_releases) do
    def initialize(path, modal_calls = [], grab_releases = [])
      super
    end

    def modal(global: false, &block)
      modal_calls << { global: global }
      block.call if block
    end

    def grab_release
      grab_releases << true
    end
  end

  FakeApp = Struct.new(:calls, :binds, :on_closes, :popups, :windows) do
    def initialize(calls = [], binds = [], on_closes = [], popups = [], windows = [])
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

    def popup_menu(menu, x:, y:, entry: nil)
      popups << { menu: menu, x: x, y: y, entry: entry }
    end

    def window(path)
      win = FakeWindow.new(path)
      windows << win
      win
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

  def test_app_raises_before_realize
    node = Teek::UI::Node.new(type: :button, name: :save)
    handle = Teek::UI::Handle.new(node)

    assert_raises(Teek::UI::NotRealizedError) { handle.app }
  end

  def test_app_returns_the_realized_app_once_realized
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :save)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: '.win.save')
    handle = Teek::UI::Handle.new(node)

    assert_same app, handle.app
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

  def test_on_right_click_queues_the_platform_appropriate_event_patterns
    node = Teek::UI::Node.new(type: :button, name: :go)
    handle = Teek::UI::Handle.new(node)

    handle.on_right_click { }

    assert_equal Teek::UI::MouseEvents::RIGHT_CLICK_EVENTS, node.events.map(&:event)
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

  def test_on_right_click_with_a_menu_queues_root_coordinate_bindings_before_realize
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    handle = Teek::UI::Handle.new(node)
    menu_node = Teek::UI::Node.new(type: :context_menu, name: :ctx)
    menu_handle = Teek::UI::Handle.new(menu_node)

    result = handle.on_right_click(menu_handle)

    assert_same handle, result, "on_right_click should return self for chaining"
    assert_equal Teek::UI::MouseEvents::RIGHT_CLICK_EVENTS.length, node.events.length
    assert_equal Teek::UI::MouseEvents::RIGHT_CLICK_EVENTS, node.events.map(&:event)
    node.events.each { |binding| assert_equal %i[root_x root_y], binding.subs }
  end

  def test_on_right_click_with_a_menu_pops_up_at_the_events_root_coordinates
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: '.board')
    handle = Teek::UI::Handle.new(node)
    menu_node = Teek::UI::Node.new(type: :context_menu, name: :ctx)
    menu_node.realized = Teek::UI::RealizedNode.new(app: app, path: '.ctx')
    menu_handle = Teek::UI::Handle.new(menu_node)

    handle.on_right_click(menu_handle)
    app.binds.first[:block].call(50, 60)

    assert_equal 1, app.popups.length
    assert_equal({ menu: '.ctx', x: 50, y: 60, entry: nil }, app.popups.first)
  end

  def test_on_right_click_with_a_menu_handle_of_the_wrong_type_raises
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    handle = Teek::UI::Handle.new(node)
    not_a_menu = Teek::UI::Handle.new(Teek::UI::Node.new(type: :button, name: :go))

    error = assert_raises(ArgumentError) { handle.on_right_click(not_a_menu) }
    assert_match(/menu/i, error.message)
  end

  def test_on_right_click_with_neither_a_menu_nor_a_block_raises
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    handle = Teek::UI::Handle.new(node)

    assert_raises(ArgumentError) { handle.on_right_click }
  end

  def test_on_right_click_with_both_a_menu_and_a_block_raises
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    handle = Teek::UI::Handle.new(node)
    menu_handle = Teek::UI::Handle.new(Teek::UI::Node.new(type: :menu, name: :m))

    error = assert_raises(ArgumentError) { handle.on_right_click(menu_handle) { } }
    assert_match(/either/i, error.message)
  end

  def test_modal_raises_before_realize
    node = Teek::UI::Node.new(type: :window, name: :settings)
    handle = Teek::UI::Handle.new(node)

    assert_raises(Teek::UI::NotRealizedError) { handle.modal }
  end

  def test_grab_release_raises_before_realize
    node = Teek::UI::Node.new(type: :window, name: :settings)
    handle = Teek::UI::Handle.new(node)

    assert_raises(Teek::UI::NotRealizedError) { handle.grab_release }
  end

  def test_modal_raises_on_a_non_window_node
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :go)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: '.go')
    handle = Teek::UI::Handle.new(node)

    error = assert_raises(ArgumentError) { handle.modal }
    assert_match(/window/i, error.message)
  end

  def test_grab_release_raises_on_a_non_window_node
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :go)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: '.go')
    handle = Teek::UI::Handle.new(node)

    error = assert_raises(ArgumentError) { handle.grab_release }
    assert_match(/window/i, error.message)
  end

  def test_modal_delegates_to_the_realized_apps_window_once_realized
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :window, name: :settings)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: '.settings')
    handle = Teek::UI::Handle.new(node)
    ran = false

    handle.modal(global: true) { ran = true }

    assert_equal 1, app.windows.length
    assert_equal '.settings', app.windows.first.path
    assert_equal [{ global: true }], app.windows.first.modal_calls
    assert ran, "the setup block should run"
  end

  def test_grab_release_delegates_to_the_realized_apps_window
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :window, name: :settings)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: '.settings')
    handle = Teek::UI::Handle.new(node)

    handle.grab_release

    assert_equal 1, app.windows.length
    assert_equal '.settings', app.windows.first.path
    assert_equal [true], app.windows.first.grab_releases
  end

  def test_show_raises_before_realize
    node = Teek::UI::Node.new(type: :window, name: :settings)
    handle = Teek::UI::Handle.new(node)

    assert_raises(Teek::UI::NotRealizedError) { handle.show }
  end

  def test_hide_raises_before_realize
    node = Teek::UI::Node.new(type: :window, name: :settings)
    handle = Teek::UI::Handle.new(node)

    assert_raises(Teek::UI::NotRealizedError) { handle.hide }
  end

  def test_show_raises_on_a_non_window_node
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :go)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: '.go')
    handle = Teek::UI::Handle.new(node)

    error = assert_raises(ArgumentError) { handle.show }
    assert_match(/window/i, error.message)
  end

  def test_hide_raises_on_a_non_window_node
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :go)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: '.go')
    handle = Teek::UI::Handle.new(node)

    error = assert_raises(ArgumentError) { handle.hide }
    assert_match(/window/i, error.message)
  end
end
