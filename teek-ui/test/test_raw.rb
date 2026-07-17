# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

class TestRaw < Minitest::Test
  include TeekTestHelper

  tk_test "ui.raw's block should run at realize, with a real, usable app" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Raw Test') do |ui|
      ui.raw { |app| app.command('ttk::label', '.raw_label', text: 'from raw') }
    end
    session.run_async
    session.app.update

    assert session.app.winfo.exists?('.raw_label')
    assert_equal 'from raw', session.app.command('.raw_label', :cget, '-text')

    session.app.destroy
  end

  tk_test "ui.raw's block should not fire during build, only at realize" do
    require 'teek/ui'

    executed = false
    session = Teek::UI.app(title: 'Raw Test') { |ui| ui.raw { |_app| executed = true } }

    refute executed, "raw block ran during build, before any interpreter existed"

    session.realize
    assert executed, "raw block did not run at realize"

    session.app.destroy
  end

  tk_test "a raw op declared before a sibling it references should still resolve its realized path" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Raw Test') do |ui|
      ui.raw { |app| app.command(ui[:later].path, :configure, text: 'Changed by raw') }
      ui.button(:later, text: 'Original')
    end
    session.run_async
    session.app.update

    assert_equal 'Changed by raw', session.app.command(session[:later].path, :cget, '-text')

    session.app.destroy
  end
end
