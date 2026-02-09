# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestButtonClick < Minitest::Test
  include TeekTestHelper

  def test_button_click_prints_hello_world
    assert_tk_app("button click should print Hello world") do
      app.command(:button, ".b", text: "click me", command: proc { puts "Hello world" })
      app.command(:pack, ".b")
      app.command(".b", "invoke")
    end
  end
end
