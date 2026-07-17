# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Real-Tk half of ui.component's coverage - scoping itself (name
# collisions, ui[:name] resolution) is pure Ruby, covered headlessly in
# test_component.rb; this confirms the realized side: two components'
# like-named children land at distinct, real Tk paths with no extra work
# needed from Realizer - allocate_path already builds a path from each
# node's OWN parent chain, and two components mounted under different
# parents are never Tk siblings of each other.
class TestComponentRealTk < Minitest::Test
  include TeekTestHelper

  tk_test "two components under different parents should realize distinct paths for their like-named children" do
    require 'teek/ui'

    save_a = nil
    save_b = nil
    session = Teek::UI.app(title: 'Component Test') do |ui|
      ui.panel(:sidebar) { |p| p.component { |c| save_a = c.button(:save, text: 'Save A') } }
      ui.panel(:main) { |p| p.component { |c| save_b = c.button(:save, text: 'Save B') } }
    end
    session.run_async
    session.app.update

    assert_equal "#{session[:sidebar].path}.save", save_a.path
    assert_equal "#{session[:main].path}.save", save_b.path
    refute_equal save_a.path, save_b.path

    assert session.app.winfo.exists?(save_a.path)
    assert session.app.winfo.exists?(save_b.path)
    assert_equal 'Save A', session.app.command(save_a.path, :cget, '-text')
    assert_equal 'Save B', session.app.command(save_b.path, :cget, '-text')

    session.app.destroy
  end

  tk_test "a component's facade should resolve to its own :save, never a sibling component's like-named one" do
    require 'teek/ui'

    facade_a = nil
    facade_b = nil
    session = Teek::UI.app(title: 'Component Test') do |ui|
      ui.panel(:sidebar) { |p| facade_a = p.component { |c| c.button(:save, text: 'Save A') } }
      ui.panel(:main) { |p| facade_b = p.component { |c| c.button(:save, text: 'Save B') } }
    end
    session.run_async
    session.app.update

    handle_a = facade_a[:save]
    handle_b = facade_b[:save]

    refute_equal handle_a.path, handle_b.path
    assert_equal 'Save A', session.app.command(handle_a.path, :cget, '-text')
    assert_equal 'Save B', session.app.command(handle_b.path, :cget, '-text')

    handle_a.configure(text: 'Changed A')
    assert_equal 'Changed A', session.app.command(handle_a.path, :cget, '-text')
    assert_equal 'Save B', session.app.command(handle_b.path, :cget, '-text'),
      "mutating component A's facade handle should never affect component B's widget"

    session.app.destroy
  end

  tk_test "mounting the same component 3x directly under one parent (not each under its own sub-panel) should realize 3 distinct :save widgets, each addressable through its own mount's facade" do
    require 'teek/ui'

    row = ->(ui, label) { ui.component { |c| c.button(:save, text: label) } }

    facades = []
    session = Teek::UI.app(title: 'Component Test') do |ui|
      ui.panel(:list) { |p| 3.times { |i| facades << row.call(p, "Row #{i + 1}") } }
    end
    session.run_async
    session.app.update

    paths = facades.map { |f| f[:save].path }
    assert_equal 3, paths.uniq.length, "each mount's :save should realize its own distinct Tk path (got #{paths.inspect})"
    assert_equal ['Row 1', 'Row 2', 'Row 3'], paths.map { |path| session.app.command(path, :cget, '-text') }

    facades[1][:save].configure(text: 'Changed')
    assert_equal 'Row 1', session.app.command(paths[0], :cget, '-text')
    assert_equal 'Changed', session.app.command(paths[1], :cget, '-text'),
      "configuring through the second mount's facade should mutate the second mount's own widget"
    assert_equal 'Row 3', session.app.command(paths[2], :cget, '-text')

    session.app.destroy
  end

  tk_test "a click handler declared inside one mount of a 3x-repeated component should fire only for that mount's own widget, never a sibling mount's" do
    require 'teek/ui'

    fired = []
    row = ->(ui, label) { ui.component { |c| c.button(:save, text: label).on_click { fired << label } } }

    facades = []
    session = Teek::UI.app(title: 'Component Test') do |ui|
      ui.panel(:list) { |p| 3.times { |i| facades << row.call(p, "Row #{i + 1}") } }
    end
    session.run_async
    session.app.update

    session.app.tcl_eval("event generate #{facades[1][:save].path} <Button-1>")
    session.app.update

    assert_equal ['Row 2'], fired, "clicking the second mount's widget should fire only its own handler"

    session.app.destroy
  end
end
