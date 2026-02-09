# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestWidgetTracking < Minitest::Test
  include TeekTestHelper

  def test_tracks_created_widgets
    assert_tk_app("should track created widgets") do
      app.command(:button, ".b", text: "hello")
      app.command(:label, ".l", text: "world")
      app.command(:frame, ".f")

      assert_equal 3, app.widgets.size
      assert app.widgets[".b"], "missing .b"
      assert_equal "Button", app.widgets[".b"][:class]
      assert_equal "Label", app.widgets[".l"][:class]
      assert_equal "Frame", app.widgets[".f"][:class]
    end
  end

  def test_tracks_destroy
    assert_tk_app("should remove destroyed widgets") do
      app.command(:button, ".b", text: "hello")
      app.command(:label, ".l", text: "world")
      assert_equal 2, app.widgets.size

      app.destroy(".b")
      assert_equal 1, app.widgets.size
      refute app.widgets[".b"], ".b should be gone"
      assert app.widgets[".l"], ".l should remain"
    end
  end

  def test_tracking_disabled
    assert_tk_app("should not track when disabled") do
      app2 = Teek::App.new(track_widgets: false)
      app2.tcl_eval("button .b -text hello")
      assert_empty app2.widgets
    end
  end
end
