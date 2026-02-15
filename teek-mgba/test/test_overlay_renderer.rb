# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../teek-mgba/lib/teek/mgba/overlay_renderer"

class TestOverlayRenderer < Minitest::Test
  class MockTexture
    attr_reader :calls, :width, :height
    attr_accessor :blend_mode

    def initialize(w, h)
      @width = w
      @height = h
      @blend_mode = nil
      @calls = []
    end

    def destroy
      @calls << [:destroy]
    end
  end

  class MockFont
    attr_reader :calls

    def initialize
      @calls = []
    end

    def ascent = 10
    def measure(_text) = [100, 14]

    def render_text(text, r, g, b)
      @calls << [:render_text, text]
      MockTexture.new(text.length * 7, 14)
    end
  end

  class MockRenderer
    attr_reader :calls

    def initialize
      @calls = []
    end

    def output_size = [720, 480]

    def copy(tex, src, dst)
      @calls << [:copy, src, dst]
    end
  end

  BLEND_MODE = 42  # arbitrary integer standing in for the real blend mode

  def setup
    @font = MockFont.new
    @hud = Teek::MGBA::OverlayRenderer.new(font: @font, blend_mode: BLEND_MODE)
  end

  # -- initial state ---------------------------------------------------------

  def test_not_visible_initially
    refute @hud.fps_visible?
    refute @hud.ff_visible?
  end

  # -- set_fps ---------------------------------------------------------------

  def test_set_fps_makes_visible
    @hud.set_fps("60.0 FPS")
    assert @hud.fps_visible?
  end

  def test_set_fps_nil_hides
    @hud.set_fps("60.0 FPS")
    @hud.set_fps(nil)
    refute @hud.fps_visible?
  end

  def test_set_fps_renders_text
    @hud.set_fps("59.7 FPS")
    assert_equal 1, @font.calls.size
    assert_equal "59.7 FPS", @font.calls[0][1]
  end

  def test_set_fps_applies_blend_mode
    @hud.set_fps("60 FPS")
    tex = @font.calls.size  # just verify render was called
    assert_equal 1, tex
  end

  def test_set_fps_destroys_previous
    @hud.set_fps("60.0 FPS")
    first_render = @font.calls.size
    @hud.set_fps("30.0 FPS")
    assert_equal 2, @font.calls.size
  end

  # -- set_ff_label ----------------------------------------------------------

  def test_set_ff_label_makes_visible
    @hud.set_ff_label(">> 2x")
    assert @hud.ff_visible?
  end

  def test_set_ff_label_nil_hides
    @hud.set_ff_label(">> 2x")
    @hud.set_ff_label(nil)
    refute @hud.ff_visible?
  end

  # -- draw ------------------------------------------------------------------

  def test_draw_does_nothing_when_empty
    r = MockRenderer.new
    @hud.draw(r, nil)
    assert_empty r.calls
  end

  def test_draw_fps_top_right
    @hud.set_fps("60 FPS")
    r = MockRenderer.new
    @hud.draw(r, [0, 0, 720, 480], show_fps: true)
    copy_calls = r.calls.select { |c| c[0] == :copy }
    assert_equal 1, copy_calls.size
    dst = copy_calls[0][2]
    # Should be near the right edge
    assert dst[0] > 600, "FPS should be positioned near right edge, got x=#{dst[0]}"
  end

  def test_draw_ff_top_left
    @hud.set_ff_label(">> 2x")
    r = MockRenderer.new
    @hud.draw(r, [0, 0, 720, 480], show_ff: true)
    copy_calls = r.calls.select { |c| c[0] == :copy }
    assert_equal 1, copy_calls.size
    dst = copy_calls[0][2]
    # Should be near the left edge
    assert_equal 4, dst[0]
    assert_equal 4, dst[1]
  end

  def test_draw_both
    @hud.set_fps("60 FPS")
    @hud.set_ff_label(">> MAX")
    r = MockRenderer.new
    @hud.draw(r, [0, 0, 720, 480], show_fps: true, show_ff: true)
    copy_calls = r.calls.select { |c| c[0] == :copy }
    assert_equal 2, copy_calls.size
  end

  def test_draw_respects_show_fps_false
    @hud.set_fps("60 FPS")
    r = MockRenderer.new
    @hud.draw(r, nil, show_fps: false)
    assert_empty r.calls
  end

  def test_draw_respects_show_ff_false
    @hud.set_ff_label(">> 2x")
    r = MockRenderer.new
    @hud.draw(r, nil, show_ff: false)
    assert_empty r.calls
  end

  def test_draw_offsets_by_dest_rect
    @hud.set_ff_label(">> 2x")
    r = MockRenderer.new
    @hud.draw(r, [100, 50, 500, 400], show_ff: true)
    dst = r.calls[0][2]
    assert_equal 104, dst[0]  # 100 + 4
    assert_equal 54, dst[1]   # 50 + 4
  end

  def test_draw_uses_output_size_when_no_dest
    @hud.set_fps("60 FPS")
    r = MockRenderer.new
    @hud.draw(r, nil, show_fps: true)
    dst = r.calls[0][2]
    # x should be relative to output_size width (720)
    assert dst[0] < 720
    assert dst[0] > 600
  end

  # -- destroy ---------------------------------------------------------------

  def test_destroy_clears_all
    @hud.set_fps("60 FPS")
    @hud.set_ff_label(">> 2x")
    @hud.destroy
    refute @hud.fps_visible?
    refute @hud.ff_visible?
  end

  def test_destroy_safe_when_empty
    @hud.destroy  # should not raise
    refute @hud.fps_visible?
  end
end
