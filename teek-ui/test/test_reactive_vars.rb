# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

class TestReactiveVars < Minitest::Test
  include TeekTestHelper

  tk_test "a var bound to a slider and a label should keep both in sync" do
    require 'teek/ui'

    speed = nil
    session = Teek::UI.app(title: 'Reactive Vars Test') do |ui|
      speed = ui.var(5)
      ui.slider(:speed_slider, from: 1, to: 10, bind: speed)
      ui.label(:speed_label, bind: speed)
    end
    session.run_async
    session.app.update

    assert_equal 5, speed.value

    slider_path = session[:speed_slider].path
    label_path = session[:speed_label].path

    # slider -> var -> label
    # ttk::scale always stores/formats its bound variable as a float
    # (e.g. "7.0"), even for a whole-number -from/-to range - compare
    # numerically rather than assuming a particular string format.
    session.app.command(slider_path, :set, 7)
    session.app.update
    assert_equal 7, speed.value
    assert_equal 7.0, session.app.command(label_path, :cget, '-text').to_f

    # var -> slider and label
    speed.value = 3
    session.app.update
    assert_equal 3.0, session.app.command(slider_path, :get).to_f
    assert_equal 3.0, session.app.command(label_path, :cget, '-text').to_f

    session.app.destroy
  end

  tk_test "a var bound to a text_box should sync in both directions" do
    require 'teek/ui'

    name = nil
    session = Teek::UI.app(title: 'Reactive Vars Test') { |ui| name = ui.var(''); ui.text_box(:name_box, bind: name) }
    session.run_async
    session.app.update

    # var -> text_box
    name.value = 'hello'
    session.app.update
    assert_equal 'hello', session.app.command(session[:name_box].path, :get)

    # text_box -> var
    box_path = session[:name_box].path
    session.app.command(box_path, :delete, 0, :end)
    session.app.command(box_path, :insert, 0, 'typed')
    session.app.update
    assert_equal 'typed', name.value

    session.app.destroy
  end

  tk_test "on_change should fire with a coerced Integer, triggered by the bound widget" do
    require 'teek/ui'

    speed = nil
    changes = []
    session = Teek::UI.app(title: 'Reactive Vars Test') do |ui|
      speed = ui.var(5)
      speed.on_change { |v| changes << v }
      ui.slider(:speed_slider, from: 1, to: 10, bind: speed)
    end
    session.run_async
    session.app.update

    session.app.command(session[:speed_slider].path, :set, 9)
    session.app.update

    assert_includes changes, 9
    assert_kind_of Integer, changes.last

    session.app.destroy
  end

  tk_test "a Boolean var bound to a checkbox should use Tk's 1/0 convention and coerce back to true/false" do
    require 'teek/ui'

    enabled = nil
    session = Teek::UI.app(title: 'Reactive Vars Test') do |ui|
      enabled = ui.var(true)
      ui.checkbox(:enabled_box, bind: enabled)
    end
    session.run_async
    session.app.update

    assert_equal true, enabled.value
    assert_equal '1', session.app.get_variable(enabled.name)

    enabled.value = false
    session.app.update
    assert_equal false, enabled.value
    assert_equal '0', session.app.get_variable(enabled.name)

    session.app.destroy
  end
end
