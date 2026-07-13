# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/node'
require 'teek/ui/handle'

class TestHandle < Minitest::Test
  FakeApp = Struct.new(:calls) do
    def command(*args, **kwargs)
      calls << [args, kwargs]
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
end
