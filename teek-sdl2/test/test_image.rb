# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test/tk_test_helper"

class TestImage < Minitest::Test
  include TeekTestHelper

  def test_load_image
    assert_tk_app("load_image returns a texture with correct dimensions") do
      require "teek/sdl2"

      png = fixture_path("teek-sdl2/assets/test_red_8x8.png")
      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)

      tex = viewport.renderer.load_image(png)
      assert_kind_of Teek::SDL2::Texture, tex
      assert_equal 8, tex.width
      assert_equal 8, tex.height
      assert_equal [8, 8], tex.size
      refute tex.destroyed?

      tex.destroy
      assert tex.destroyed?
      viewport.destroy
    end
  end

  def test_load_image_and_render
    assert_tk_app("load_image texture can be rendered") do
      require "teek/sdl2"

      png = fixture_path("teek-sdl2/assets/test_red_8x8.png")
      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)
      viewport.pack

      tex = viewport.renderer.load_image(png)

      viewport.render do |r|
        r.clear(0, 0, 0)
        r.copy(tex, nil, [0, 0, tex.width * 4, tex.height * 4])
      end

      tex.destroy
      viewport.destroy
    end
  end

  def test_texture_from_file
    assert_tk_app("Texture.from_file convenience works") do
      require "teek/sdl2"

      png = fixture_path("teek-sdl2/assets/test_red_8x8.png")
      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)

      tex = Teek::SDL2::Texture.from_file(viewport.renderer, png)
      assert_kind_of Teek::SDL2::Texture, tex
      assert_equal 8, tex.width
      assert_equal 8, tex.height

      tex.destroy
      viewport.destroy
    end
  end

  def test_load_image_bad_path
    assert_tk_app("load_image raises on missing file") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)

      assert_raises(RuntimeError) do
        viewport.renderer.load_image("/nonexistent/path/to/image.png")
      end

      viewport.destroy
    end
  end
end
