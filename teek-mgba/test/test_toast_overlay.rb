# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../teek-mgba/lib/teek/mgba/toast_overlay"

class TestToastOverlay < Minitest::Test
  # Minimal texture mock — records destroy calls.
  class MockTexture
    attr_reader :calls, :width, :height
    attr_accessor :blend_mode

    def initialize(w, h)
      @width = w
      @height = h
      @blend_mode = nil
      @calls = []
    end

    def update(pixels)
      @calls << [:update, pixels.bytesize]
    end

    def destroy
      @calls << [:destroy]
    end
  end

  # Recording renderer mock.
  class MockRenderer
    attr_reader :calls, :textures

    def initialize
      @calls = []
      @textures = []
    end

    def create_texture(w, h, mode)
      tex = MockTexture.new(w, h)
      @textures << tex
      @calls << [:create_texture, w, h, mode]
      tex
    end

    def output_size
      [720, 480]
    end

    def copy(tex, src, dst)
      @calls << [:copy, src, dst]
    end
  end

  # Recording font mock.
  class MockFont
    attr_reader :calls

    def initialize
      @calls = []
    end

    def ascent
      10
    end

    def measure(_text)
      [100, 14]
    end

    def render_text(text, r, g, b)
      @calls << [:render_text, text, r, g, b]
      MockTexture.new(text.length * 7, 14)
    end
  end

  # Stub for the C-implemented toast_background — returns dummy ARGB pixels.
  STUB_BG_FN = ->(w, h, _radius) { "\x00".b * (w * h * 4) }

  def setup
    @renderer = MockRenderer.new
    @font = MockFont.new
    @toast = Teek::MGBA::ToastOverlay.new(
      renderer: @renderer, font: @font, duration: 1.5, bg_fn: STUB_BG_FN
    )
  end

  # -- visibility ------------------------------------------------------------

  def test_not_visible_initially
    refute @toast.visible?
  end

  def test_visible_after_show
    @toast.show("Hello")
    assert @toast.visible?
  end

  def test_not_visible_after_destroy
    @toast.show("Hello")
    @toast.destroy
    refute @toast.visible?
  end

  # -- show ------------------------------------------------------------------

  def test_show_renders_text
    @toast.show("Saved")
    render_calls = @font.calls.select { |c| c[0] == :render_text }
    assert_equal 1, render_calls.size
    assert_equal "Saved", render_calls[0][1]
    # White text
    assert_equal [255, 255, 255], render_calls[0][2..4]
  end

  def test_show_creates_background_texture
    @toast.show("Saved")
    create_calls = @renderer.calls.select { |c| c[0] == :create_texture }
    assert_equal 1, create_calls.size
    # Background should be wider than text (padded)
    assert create_calls[0][1] > 0
    assert create_calls[0][2] > 0
    assert_equal :streaming, create_calls[0][3]
  end

  def test_show_replaces_previous_toast
    @toast.show("First")
    @toast.show("Second")
    # Should have rendered text twice
    render_calls = @font.calls.select { |c| c[0] == :render_text }
    assert_equal 2, render_calls.size
    assert_equal "Second", render_calls[1][1]
    # First toast's textures should have been destroyed
    first_bg = @renderer.textures[0]
    assert first_bg.calls.any? { |c| c[0] == :destroy }
  end

  # -- draw ------------------------------------------------------------------

  def test_draw_does_nothing_when_no_toast
    r = MockRenderer.new
    @toast.draw(r, nil)
    assert_empty r.calls
  end

  def test_draw_copies_bg_and_text
    @toast.show("Hello")
    r = MockRenderer.new
    @toast.draw(r, [0, 0, 720, 480])
    copy_calls = r.calls.select { |c| c[0] == :copy }
    assert_equal 2, copy_calls.size  # background + text
  end

  def test_draw_centers_in_dest_rect
    @toast.show("Hi")
    r = MockRenderer.new
    @toast.draw(r, [100, 0, 500, 400])
    copy_calls = r.calls.select { |c| c[0] == :copy }
    # Background dest rect x should be centered around 100 + 250 = 350
    bg_dst = copy_calls[0][2]
    cx = 100 + 500 / 2
    assert_equal cx - bg_dst[2] / 2, bg_dst[0]
  end

  def test_draw_uses_output_size_when_no_dest
    @toast.show("Hi")
    r = MockRenderer.new
    @toast.draw(r, nil)
    copy_calls = r.calls.select { |c| c[0] == :copy }
    bg_dst = copy_calls[0][2]
    # Should center around output_size width / 2 = 360
    assert_equal 360 - bg_dst[2] / 2, bg_dst[0]
  end

  # -- expiration ------------------------------------------------------------

  def test_draw_destroys_expired_toast
    @toast.show("Bye", duration: 0.0)
    sleep 0.01  # ensure expired
    r = MockRenderer.new
    @toast.draw(r, nil)
    # Should have self-destroyed, no copy calls
    assert_empty r.calls.select { |c| c[0] == :copy }
    refute @toast.visible?
  end

  def test_permanent_toast_does_not_expire
    @toast.show("Wait", permanent: true)
    sleep 0.01
    r = MockRenderer.new
    @toast.draw(r, [0, 0, 720, 480])
    copy_calls = r.calls.select { |c| c[0] == :copy }
    assert_equal 2, copy_calls.size
    assert @toast.visible?
  end

  # -- destroy ---------------------------------------------------------------

  def test_destroy_frees_textures
    @toast.show("Hello")
    bg_tex = @renderer.textures.last
    @toast.destroy
    assert bg_tex.calls.any? { |c| c[0] == :destroy }
  end

  def test_destroy_is_safe_when_empty
    @toast.destroy  # no-op, should not raise
    refute @toast.visible?
  end

  # -- duration accessor -----------------------------------------------------

  def test_duration_accessor
    assert_in_delta 1.5, @toast.duration
    @toast.duration = 3.0
    assert_in_delta 3.0, @toast.duration
  end
end
