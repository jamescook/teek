# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/image'

class TestImage < Minitest::Test
  def test_name_is_the_allocated_tcl_image_name
    image = Teek::UI::Image.new('teek_ui_image_1', '/tmp/whatever.png', {})

    assert_equal 'teek_ui_image_1', image.name
  end

  def test_to_s_is_the_allocated_tcl_image_name
    image = Teek::UI::Image.new('teek_ui_image_1', '/tmp/whatever.png', {})

    assert_equal 'teek_ui_image_1', image.to_s
  end

  def test_photo_raises_before_realize
    image = Teek::UI::Image.new('teek_ui_image_1', '/tmp/whatever.png', {})

    assert_raises(Teek::UI::NotRealizedError) { image.photo }
  end
end
