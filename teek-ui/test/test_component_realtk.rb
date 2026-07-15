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

  def test_two_components_like_named_children_get_distinct_tk_paths
    assert_tk_app("two components under different parents should realize distinct paths for their like-named children") do
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
  end
end
