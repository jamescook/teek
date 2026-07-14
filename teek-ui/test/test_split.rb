# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# ui.split/s.pane realize as a working ttk::panedwindow - each pane a real
# Tk frame added as a managed pane (Realizer#setup_pane), never pack/grid
# managed on its own (NOT_ARRANGED_TYPES).
class TestSplit < Minitest::Test
  include TeekTestHelper

  def test_split_realizes_as_a_working_panedwindow_with_panes
    assert_tk_app("ui.split should realize as a ttk::panedwindow with each pane added as a managed region") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Split Test') do |ui|
        ui.split(:s) do |s|
          s.pane { |a| a.button(:go, text: 'Go') }
          s.pane { |b| b.label(:info, text: 'Info') }
        end
      end
      session.run_async
      session.app.update

      split_path = session[:s].path
      pane_paths = session.app.split_list(session.app.command(split_path, :panes))
      assert_equal 2, pane_paths.length

      session.app.destroy
    end
  end

  def test_pane_content_is_addressable_and_configurable_like_any_other_widget
    assert_tk_app("a widget declared inside a pane should be a normal, addressable, configurable widget") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Split Test') do |ui|
        ui.split { |s| s.pane { |a| a.button(:go, text: 'Go') } }
      end
      session.run_async
      session.app.update

      session[:go].configure(text: 'Changed')
      session.app.update

      assert_equal 'Changed', session.app.command(session[:go].path, :cget, '-text')

      session.app.destroy
    end
  end

  def test_pane_frame_is_not_independently_pack_or_grid_managed
    assert_tk_app("a pane's own frame should be placed only by panedwindow add, not pack/grid") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Split Test') do |ui|
        ui.split(:s) { |s| s.pane(:left) { |a| a.button(text: 'Go') } }
      end
      session.run_async
      session.app.update

      assert_equal 'panedwindow', session.app.tcl_eval("winfo manager #{session[:left].path}"),
        "the panedwindow itself should be the only geometry manager - proves no pack/grid call also ran"

      session.app.destroy
    end
  end

  def test_split_defaults_to_horizontal_orientation
    assert_tk_app("ui.split with no orientation given should realize with -orient horizontal") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Split Test') do |ui|
        ui.split(:s) { |s| s.pane { } }
      end
      session.run_async
      session.app.update

      assert_equal 'horizontal', session.app.command(session[:s].path, :cget, '-orient')

      session.app.destroy
    end
  end

  def test_split_vertical_orientation_sets_the_real_tk_orient_option
    assert_tk_app("ui.split(orientation: :vertical) should realize with -orient vertical") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Split Test') do |ui|
        ui.split(:s, orientation: :vertical) { |s| s.pane { } }
      end
      session.run_async
      session.app.update

      assert_equal 'vertical', session.app.command(session[:s].path, :cget, '-orient')

      session.app.destroy
    end
  end

  def test_pane_weight_is_passed_through_to_panedwindow_add
    assert_tk_app("s.pane(weight:) should set the real -weight panedwindow uses to divide leftover space") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Split Test') do |ui|
        ui.split(:s) do |s|
          s.pane(:left, weight: 1) { }
          s.pane(:right, weight: 3) { }
        end
      end
      session.run_async
      session.app.update

      split_path = session[:s].path
      assert_equal '1', session.app.command(split_path, :pane, session[:left].path, '-weight')
      assert_equal '3', session.app.command(split_path, :pane, session[:right].path, '-weight')

      session.app.destroy
    end
  end

  def test_a_new_pane_can_be_added_at_runtime_via_incremental_realize
    assert_tk_app("session.add should be able to add a whole new pane to an already-realized ui.split") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Split Test') do |ui|
        ui.split(:s) { |s| s.pane { |a| a.button(text: 'Go') } }
      end
      session.run_async
      session.app.update

      split_path = session[:s].path
      assert_equal 1, session.app.split_list(session.app.command(split_path, :panes)).length

      session.add(:s) { |a| a.pane(:new_pane) { |n| n.button(:new_button, text: 'New') } }
      session.app.update

      pane_paths = session.app.split_list(session.app.command(split_path, :panes))
      assert_equal 2, pane_paths.length
      assert session.app.winfo.ismapped?(session[:new_button].path)

      session.app.destroy
    end
  end
end
