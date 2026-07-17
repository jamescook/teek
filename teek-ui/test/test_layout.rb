# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

class TestLayout < Minitest::Test
  include TeekTestHelper

  tk_test "column should stack children vertically with `gap` pixels between them" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Layout Test') do |ui|
      ui.column(:c, gap: 20) do |c|
        c.button(:a, text: 'A')
        c.button(:b, text: 'B')
      end
    end
    session.run_async
    session.app.update

    a_bottom = session.app.winfo.rooty(session[:a].path) + session.app.winfo.height(session[:a].path)
    b_top = session.app.winfo.rooty(session[:b].path)

    assert_equal 20, b_top - a_bottom
  end

  tk_test "row should stack children horizontally with `gap` pixels between them" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Layout Test') do |ui|
      ui.row(:r, gap: 15) do |r|
        r.button(:a, text: 'A')
        r.button(:b, text: 'B')
      end
    end
    session.run_async
    session.app.update

    a_right = session.app.winfo.rootx(session[:a].path) + session.app.winfo.width(session[:a].path)
    b_left = session.app.winfo.rootx(session[:b].path)

    assert_equal 15, b_left - a_right
  end

  tk_test "align: :stretch should make a narrower child match the widest sibling's width" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Layout Test') do |ui|
      ui.column(:c, align: :stretch) do |c|
        c.button(:narrow, text: 'Go')
        c.button(:wide, text: 'A Much Longer Button Label')
      end
    end
    session.run_async
    session.app.update

    narrow_width = session.app.winfo.width(session[:narrow].path)
    wide_width = session.app.winfo.width(session[:wide].path)

    assert_equal wide_width, narrow_width
  end

  tk_test "without align: :stretch, a narrower child should keep its own natural width" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Layout Test') do |ui|
      ui.column(:c) do |c|
        c.button(:narrow, text: 'Go')
        c.button(:wide, text: 'A Much Longer Button Label')
      end
    end
    session.run_async
    session.app.update

    narrow_width = session.app.winfo.width(session[:narrow].path)
    wide_width = session.app.winfo.width(session[:wide].path)

    refute_equal wide_width, narrow_width
  end

  tk_test "pad: should add space before the first child and after the last" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Layout Test') do |ui|
      ui.column(:c, pad: 10) { |c| c.button(:only, text: 'Only') }
    end
    session.run_async
    session.app.update

    col_top = session.app.winfo.rooty(session[:c].path)
    only_top = session.app.winfo.rooty(session[:only].path)

    assert_equal 10, only_top - col_top
  end

  tk_test "a spacer should absorb leftover space, pushing what follows it to the bottom - the spring-row replacement" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Layout Test') do |ui|
      ui.column(:c, height: 300) do |c|
        c.button(:top, text: 'Top')
        c.spacer
        c.button(:bottom, text: 'Bottom')
      end
    end
    session.run_async
    # disable geometry propagation so the column keeps its explicit height
    # instead of shrinking to fit its (currently tiny) content - this is
    # test setup via the escape hatch, not part of the ported app code.
    session.app.tcl_eval("pack propagate #{session[:c].path} 0")
    session.app.update

    col_bottom = session.app.winfo.rooty(session[:c].path) + session.app.winfo.height(session[:c].path)
    bottom_button_bottom = session.app.winfo.rooty(session[:bottom].path) + session.app.winfo.height(session[:bottom].path)

    # the bottom button should end close to the column's own bottom edge,
    # not sitting right under the top button
    assert_in_delta col_bottom, bottom_button_bottom, 2

    top_bottom = session.app.winfo.rooty(session[:top].path) + session.app.winfo.height(session[:top].path)
    bottom_top = session.app.winfo.rooty(session[:bottom].path)
    assert_operator (bottom_top - top_bottom), :>, 100, "the spacer should have absorbed most of the leftover height"
  end

  tk_test "goldberg's control panel column should realize correctly using only column/gap/align/spacer" do
    require 'teek/ui'

    speed = nil
    session = Teek::UI.app(title: 'Layout Test') do |ui|
      speed = ui.var(5)
      ui.column(:ctrl, gap: 4, align: :stretch, pad: 5) do |c|
        c.button(:start, text: 'Start')
        c.checkbox(:pause, text: 'Pause')
        c.button(:step, text: 'Single Step')
        c.button(:bstep, text: 'Big Step')
        c.button(:reset, text: 'Reset')
        c.checkbox(:details, text: 'Details')
        c.spacer
        c.text_box(:msg_entry)
        c.slider(:speed_scale, from: 1, to: 10, bind: speed)
        c.button(:about, text: 'About')
      end
    end
    session.run_async
    session.app.update

    %i[start pause step bstep reset details msg_entry speed_scale about].each do |name|
      path = session[name].path
      assert session.app.winfo.exists?(path), "#{name} should exist"
      assert session.app.winfo.ismapped?(path), "#{name} should be mapped/visible"
    end

    # every widget stretches to the column's own width (align: :stretch)
    widths = %i[start pause about].map { |n| session.app.winfo.width(session[n].path) }
    assert_equal 1, widths.uniq.length
  end
end
