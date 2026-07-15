# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

class TestIncrementalRealize < Minitest::Test
  include TeekTestHelper

  def test_add_creates_and_shows_new_widgets_in_a_running_app
    assert_tk_app("ui.add should create and show new widgets in an already-running app") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Incremental Realize Test') { |ui| ui.column(:list) }
      session.run_async
      session.app.update

      session.add(:list) { |a| a.button(:item1, text: 'Item 1') }
      session.app.update

      assert session.app.winfo.exists?(session[:item1].path)
      assert session.app.winfo.ismapped?(session[:item1].path)

      session.app.destroy
    end
  end

  def test_add_respects_gap_relative_to_pre_existing_siblings
    assert_tk_app("a widget added to a flow container should respect gap: relative to widgets already there") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Incremental Realize Test') do |ui|
        ui.column(:list, gap: 20) { |c| c.button(:first, text: 'First') }
      end
      session.run_async
      session.app.update

      session.add(:list) { |a| a.button(:second, text: 'Second') }
      session.app.update

      first_bottom = session.app.winfo.rooty(session[:first].path) + session.app.winfo.height(session[:first].path)
      second_top = session.app.winfo.rooty(session[:second].path)

      assert_equal 20, second_top - first_bottom

      session.app.destroy
    end
  end

  def test_events_wired_inside_add_fire_correctly
    assert_tk_app("on_click wired inside an add block should fire, using the same queue-then-wire-at-link path the initial build uses") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Incremental Realize Test') { |ui| ui.column(:list) }
      session.run_async
      session.app.update

      clicked = false
      session.add(:list) { |a| a.button(:item1, text: 'Item 1').on_click { clicked = true } }
      session.app.update

      session.app.tcl_eval("event generate #{session[:item1].path} <Button-1>")
      session.app.update

      assert clicked, "on_click wired inside ui.add did not fire"

      session.app.destroy
    end
  end

  def test_destroying_an_added_widget_reclaims_its_callback
    assert_tk_app("destroying an incrementally-added widget should release its callback via teek's existing <Destroy> machinery") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Incremental Realize Test') { |ui| ui.column(:list) }
      session.run_async
      session.app.update
      baseline = session.app.interp.callback_ids.length

      session.add(:list) { |a| a.button(:item1, text: 'Item 1').on_click { } }
      session.app.update
      assert_equal baseline + 1, session.app.interp.callback_ids.length, "adding should register one callback"

      session.app.destroy(session[:item1].path)
      session.app.update

      assert_equal baseline, session.app.interp.callback_ids.length, "destroying the added widget should release its callback"

      session.app.destroy
    end
  end

  def test_a_var_declared_inside_add_is_realized_and_works
    assert_tk_app("ui.var declared inside an add block should get its backing Tcl variable, not stay forever unrealized") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Incremental Realize Test') { |ui| ui.column(:list) }
      session.run_async
      session.app.update

      count = nil
      session.add(:list) do |a|
        count = a.var(5)
        a.label(:count_label, bind: count)
      end
      session.app.update

      assert_equal 5, count.value
      assert_equal '5', session.app.command(session[:count_label].path, :cget, '-text')

      count.value = 9
      session.app.update
      assert_equal '9', session.app.command(session[:count_label].path, :cget, '-text')

      session.app.destroy
    end
  end

  def test_an_image_declared_inside_add_is_realized_and_displays
    assert_tk_app("ui.image declared inside an add block should actually load, not raise 'image does not exist' - the ChildWindow fresh-mount-per-open pattern depends on this") do
      require 'teek/ui'
      require 'tmpdir'

      Dir.mktmpdir do |dir|
        path = File.join(dir, 'test.png')
        seed = Teek::Photo.new(app, width: 4, height: 4)
        seed.put_block(([0, 0, 0, 255].pack('CCCC')) * 16, 4, 4)
        app.tcl_eval("#{seed.name} write {#{path}} -format png")
        seed.delete

        session = Teek::UI.app(title: 'Incremental Realize Test') { |ui| ui.column(:list) }
        session.run_async
        session.app.update

        icon = nil
        session.add(:list) do |a|
          icon = a.image(path)
          a.label(:pic, image: icon)
        end
        session.app.update

        assert_equal icon.name, session.app.command(session[:pic].path, :cget, '-image')
        assert_equal 'photo', session.app.tcl_eval("image type #{icon.name}")

        session.app.destroy
      end
    end
  end

  def test_add_on_an_unrealized_session_raises
    assert_tk_app("ui.add before the session is realized should raise a clear error") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Incremental Realize Test') { |ui| ui.column(:list) }

      assert_raises(Teek::UI::NotRealizedError) { session.add(:list) { |a| a.button(:item1) } }
    end
  end

  def test_add_to_an_unknown_parent_name_raises
    assert_tk_app("ui.add with a name that doesn't exist should raise a clear error") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Incremental Realize Test') { |ui| ui.column(:list) }
      session.run_async
      session.app.update

      error = assert_raises(ArgumentError) { session.add(:nope) { |a| a.button(:item1) } }
      assert_match(/nope/, error.message)

      session.app.destroy
    end
  end
end
