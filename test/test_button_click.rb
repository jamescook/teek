# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestButtonClick < Minitest::Test
  include TeekTestHelper

  tk_test "button click should print Hello world" do
    app.command(:button, ".b", text: "click me", command: proc { puts "Hello world" })
    app.command(:pack, ".b")
    app.command(".b", "invoke")
  end
end
