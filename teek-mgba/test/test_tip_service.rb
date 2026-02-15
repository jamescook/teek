# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test/tk_test_helper"

class TestTipService < Minitest::Test
  include TeekTestHelper

  def test_register_sets_underline_font
    assert_tk_app("register sets underlined font") do
      require "teek/mgba/tip_service"
      tips = Teek::MGBA::TipService.new(app)

      lbl = ".test_lbl"
      app.command('ttk::label', lbl, text: "Test")
      app.command(:pack, lbl)
      app.update

      tips.register(lbl, "Help text")
      app.update

      font = app.command(lbl, 'cget', '-font')
      underline = app.tcl_eval("font actual #{font} -underline")
      assert_equal '1', underline
    end
  end

  def test_show_creates_tooltip
    assert_tk_app("show creates a tooltip toplevel") do
      require "teek/mgba/tip_service"
      tips = Teek::MGBA::TipService.new(app)

      lbl = ".test_lbl"
      app.command('ttk::label', lbl, text: "Test")
      app.command(:pack, lbl)
      app.show
      app.update

      refute tips.showing?
      tips.show(lbl, "Help text")
      app.update

      assert tips.showing?
      assert_equal lbl, tips.target
    end
  end

  def test_hide_destroys_tooltip
    assert_tk_app("hide destroys tooltip") do
      require "teek/mgba/tip_service"
      tips = Teek::MGBA::TipService.new(app)

      lbl = ".test_lbl"
      app.command('ttk::label', lbl, text: "Test")
      app.command(:pack, lbl)
      app.show
      app.update

      tips.show(lbl, "Help text")
      app.update
      assert tips.showing?

      tips.hide
      app.update
      refute tips.showing?
      assert_nil tips.target
    end
  end

  def test_toggle_behavior
    assert_tk_app("clicking same label toggles tooltip") do
      require "teek/mgba/tip_service"
      tips = Teek::MGBA::TipService.new(app)

      lbl = ".test_lbl"
      app.command('ttk::label', lbl, text: "Test")
      app.command(:pack, lbl)
      app.show
      app.update

      tips.register(lbl, "Help text")
      app.update

      # First click — show
      app.command(:event, 'generate', lbl, '<Button-1>')
      app.update
      assert tips.showing?
      assert_equal lbl, tips.target

      # Second click — hide
      app.command(:event, 'generate', lbl, '<Button-1>')
      app.update
      refute tips.showing?
    end
  end

  def test_only_one_tooltip_at_a_time
    assert_tk_app("showing a second tooltip hides the first") do
      require "teek/mgba/tip_service"
      tips = Teek::MGBA::TipService.new(app)

      lbl1 = ".test_lbl1"
      lbl2 = ".test_lbl2"
      app.command('ttk::label', lbl1, text: "Label 1")
      app.command('ttk::label', lbl2, text: "Label 2")
      app.command(:pack, lbl1)
      app.command(:pack, lbl2)
      app.show
      app.update

      tips.register(lbl1, "Help 1")
      tips.register(lbl2, "Help 2")
      app.update

      # Show first tooltip
      tips.show(lbl1, "Help 1")
      app.update
      assert_equal lbl1, tips.target

      # Show second — first should be gone
      tips.show(lbl2, "Help 2")
      app.update
      assert_equal lbl2, tips.target
    end
  end

  def test_dismiss_ms_is_configurable
    assert_tk_app("dismiss_ms is configurable") do
      require "teek/mgba/tip_service"
      tips = Teek::MGBA::TipService.new(app, dismiss_ms: 2000)

      assert_equal 2000, tips.dismiss_ms

      tips.dismiss_ms = 5000
      assert_equal 5000, tips.dismiss_ms
    end
  end
end
