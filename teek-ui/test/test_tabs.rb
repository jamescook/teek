# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# ui.tabs/t.tab realize as a working ttk::notebook - each tab a real Tk
# frame added as a notebook page (TabRealize.post_create), never pack/grid
# managed on its own (:tab's own arranged: false). Tab selection is
# observable via Handle#on_tab_changed, which surfaces Tk's own
# <<NotebookTabChanged>>.
class TestTabs < Minitest::Test
  include TeekTestHelper

  tk_test "ui.tabs should realize as a ttk::notebook with each tab added as a labeled page" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Tabs Test') do |ui|
      ui.tabs(:t) do |t|
        t.tab('General') { |g| g.button(:go, text: 'Go') }
        t.tab('Advanced') { |a| a.label(:info, text: 'Advanced stuff') }
      end
    end
    session.run_async
    session.app.update

    notebook_path = session[:t].path
    tab_paths = session.app.split_list(session.app.command(notebook_path, :tabs))
    assert_equal 2, tab_paths.length

    assert_equal 'General', session.app.command(notebook_path, :tab, tab_paths[0], '-text')
    assert_equal 'Advanced', session.app.command(notebook_path, :tab, tab_paths[1], '-text')

    session.app.destroy
  end

  tk_test "a widget declared inside a tab should be a normal, addressable, configurable widget" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Tabs Test') do |ui|
      ui.tabs { |t| t.tab('General') { |g| g.button(:go, text: 'Go') } }
    end
    session.run_async
    session.app.update

    session[:go].configure(text: 'Changed')
    session.app.update

    assert_equal 'Changed', session.app.command(session[:go].path, :cget, '-text')

    session.app.destroy
  end

  tk_test "a tab's own frame should be placed only by notebook add, not pack/grid" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Tabs Test') do |ui|
      ui.tabs(:t) { |t| t.tab('General', :general) { |g| g.button(text: 'Go') } }
    end
    session.run_async
    session.app.update

    assert_equal 'notebook', session.app.tcl_eval("winfo manager #{session[:general].path}"),
      "the notebook itself should be the only geometry manager - proves no pack/grid call also ran"

    session.app.destroy
  end

  tk_test "switching to a named tab should fire on_tab_changed with that name" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Tabs Test') do |ui|
      ui.tabs(:t) do |t|
        t.tab('General', :general) { }
        t.tab('Advanced', :advanced) { }
      end
    end
    session.run_async
    session.app.update

    received = []
    session[:t].on_tab_changed { |id| received << id }

    session.app.command(session[:t].path, :select, session[:advanced].path)
    session.app.update

    assert_equal [:advanced], received

    session.app.destroy
  end

  tk_test "switching to an unnamed tab should fire on_tab_changed with its zero-based index" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Tabs Test') do |ui|
      ui.tabs(:t) do |t|
        t.tab('General') { }
        t.tab('Advanced') { }
      end
    end
    session.run_async
    session.app.update

    received = []
    session[:t].on_tab_changed { |id| received << id }

    notebook_path = session[:t].path
    second_tab = session.app.split_list(session.app.command(notebook_path, :tabs))[1]
    session.app.command(notebook_path, :select, second_tab)
    session.app.update

    assert_equal [1], received

    session.app.destroy
  end

  tk_test "on_tab_changed declared before realize should still fire correctly once realized" do
    require 'teek/ui'

    tabs_handle = nil
    session = Teek::UI.app(title: 'Tabs Test') do |ui|
      tabs_handle = ui.tabs(:t) do |t|
        t.tab('General', :general) { }
        t.tab('Advanced', :advanced) { }
      end
    end

    received = []
    tabs_handle.on_tab_changed { |id| received << id }

    session.run_async
    session.app.update
    # realizing the notebook auto-selects its first tab, which is a real
    # <<NotebookTabChanged>> in its own right and (since this binding
    # was queued before realize, unlike the other on_tab_changed tests)
    # gets caught by it too - clear that out to isolate the transition
    # this test actually cares about.
    received.clear

    session.app.command(session[:t].path, :select, session[:advanced].path)
    session.app.update

    assert_equal [:advanced], received

    session.app.destroy
  end

  tk_test "on_tab_changed should raise a clear error on a non-tabs handle" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Tabs Test') { |ui| ui.button(:go, text: 'Go') }
    session.run_async
    session.app.update

    error = assert_raises(ArgumentError) { session[:go].on_tab_changed { } }
    assert_match(/tabs/i, error.message)

    session.app.destroy
  end

  tk_test "session.add should be able to add a whole new tab to an already-realized ui.tabs" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Tabs Test') do |ui|
      ui.tabs(:t) { |t| t.tab('General') { |g| g.button(text: 'Go') } }
    end
    session.run_async
    session.app.update

    notebook_path = session[:t].path
    assert_equal 1, session.app.split_list(session.app.command(notebook_path, :tabs)).length

    session.add(:t) { |a| a.tab('New Tab', :new_tab) { |n| n.button(:new_button, text: 'New') } }
    session.app.update

    tab_paths = session.app.split_list(session.app.command(notebook_path, :tabs))
    assert_equal 2, tab_paths.length
    assert_equal 'New Tab', session.app.command(notebook_path, :tab, tab_paths[1], '-text')

    session.app.command(notebook_path, :select, session[:new_tab].path)
    session.app.update
    assert session.app.winfo.ismapped?(session[:new_button].path)

    session.app.destroy
  end
end
