# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test/tk_test_helper"

class TestRenderer < Minitest::Test
  include TeekTestHelper

  def test_fill
    assert_tk_app("fill draws a filled rectangle") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)

      r = viewport.renderer
      r.clear
      r.fill(10, 10, 50, 50, r: 255, g: 0, b: 0)
      assert_sdl2_screenshot(r, "fill")
      r.present

      viewport.destroy
    end
  end

  def test_outline
    assert_tk_app("outline draws a rectangle outline") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)

      r = viewport.renderer
      r.clear(40, 40, 40)
      r.fill(10, 10, 180, 180, r: 0, g: 100, b: 0)
      r.outline(10, 10, 180, 180, r: 0, g: 255, b: 0)
      assert_sdl2_screenshot(r, "outline")
      r.present

      viewport.destroy
    end
  end

  def test_line
    assert_tk_app("line draws between two points") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)

      r = viewport.renderer
      r.clear(40, 40, 40)
      r.line(0, 0, 199, 199, r: 255, g: 255, b: 0)
      r.line(0, 199, 199, 0, r: 0, g: 255, b: 255)
      assert_sdl2_screenshot(r, "line")
      r.present

      viewport.destroy
    end
  end

  def test_blit
    assert_tk_app("blit copies a texture to the renderer") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)

      tex = viewport.renderer.create_texture(64, 64, :streaming)
      pixels = ([0xFF, 0x00, 0xFF, 0x00].pack('C*') * (64 * 64))
      tex.update(pixels)

      r = viewport.renderer
      r.clear
      r.blit(tex, dst: [10, 10, 64, 64])
      assert_sdl2_screenshot(r, "blit")
      r.present

      tex.destroy
      viewport.destroy
    end
  end

  def test_combined_rendering
    assert_tk_app("all draw methods work together in one frame") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 300, height: 300)

      tex = viewport.renderer.create_texture(32, 32, :streaming)
      pixels = ([0xFF, 0x80, 0x80, 0x80].pack('C*') * (32 * 32))
      tex.update(pixels)

      r = viewport.renderer
      r.clear(0, 0, 0)
      r.fill(10, 10, 100, 100, r: 255, g: 0, b: 0)
      r.outline(120, 10, 100, 100, r: 0, g: 255, b: 0)
      r.line(10, 200, 290, 200, r: 0, g: 0, b: 255)
      r.blit(tex, dst: [130, 130, 32, 32])
      assert_sdl2_screenshot(r, "combined")
      r.present

      tex.destroy
      viewport.destroy
    end
  end

  def test_read_pixels
    assert_tk_app("read_pixels returns RGBA buffer matching output size") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 64, height: 64)

      r = viewport.renderer
      r.clear(255, 0, 0)

      pixels = r.read_pixels
      w, h = r.output_size
      assert_equal w * h * 4, pixels.bytesize

      # First pixel should be red (RGBA: 255, 0, 0, 255)
      rgba = pixels.byteslice(0, 4).unpack('C4')
      assert_equal 255, rgba[0], "red channel"
      assert_equal 0,   rgba[1], "green channel"
      assert_equal 0,   rgba[2], "blue channel"

      viewport.destroy
    end
  end
end
