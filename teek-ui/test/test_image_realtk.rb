# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Real-Tk half of image support's coverage - Image's own build-time shape
# (name allocation, raises before realize) is covered headlessly in
# test_image.rb; these exercise the actual load-and-display path against
# a real Tk photo image.
class TestImageRealTk < Minitest::Test
  include TeekTestHelper

  tk_test "ui.image(path) + image: on a label should load and display a real Tk photo image" do
    require 'teek/ui'
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.png')
      seed = Teek::Photo.new(app, width: 8, height: 8)
      red = ([255, 0, 0, 255].pack('CCCC')) * (8 * 8)
      seed.put_block(red, 8, 8)
      app.tcl_eval("#{seed.name} write {#{path}} -format png")
      seed.delete

      icon = nil
      session = Teek::UI.app(title: 'Image Test') do |ui|
        icon = ui.image(path)
        ui.label(:pic, image: icon)
      end
      session.run_async
      session.app.update

      pic_path = session[:pic].path
      assert_equal icon.name, session.app.command(pic_path, :cget, '-image')
      assert_equal 'photo', session.app.tcl_eval("image type #{icon.name}")
      w, h = icon.photo.get_size
      assert_equal 8, w
      assert_equal 8, h

      session.app.destroy
    end
  end

  tk_test "ui.image(path) + image: on a button should load and display a real Tk photo image" do
    require 'teek/ui'
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.png')
      seed = Teek::Photo.new(app, width: 8, height: 8)
      blue = ([0, 0, 255, 255].pack('CCCC')) * (8 * 8)
      seed.put_block(blue, 8, 8)
      app.tcl_eval("#{seed.name} write {#{path}} -format png")
      seed.delete

      icon = nil
      session = Teek::UI.app(title: 'Image Test') do |ui|
        icon = ui.image(path)
        ui.button(:go, image: icon)
      end
      session.run_async
      session.app.update

      assert_equal icon.name, session.app.command(session[:go].path, :cget, '-image')

      session.app.destroy
    end
  end

  tk_test "handle.configure(image: another_image) should swap the displayed image" do
    require 'teek/ui'
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      path_a = File.join(dir, 'a.png')
      path_b = File.join(dir, 'b.png')
      [path_a, path_b].each_with_index do |path, i|
        seed = Teek::Photo.new(app, width: 4, height: 4)
        color = i.zero? ? [255, 0, 0, 255] : [0, 255, 0, 255]
        seed.put_block((color.pack('CCCC')) * 16, 4, 4)
        app.tcl_eval("#{seed.name} write {#{path}} -format png")
        seed.delete
      end

      icon_a = nil
      icon_b = nil
      session = Teek::UI.app(title: 'Image Test') do |ui|
        icon_a = ui.image(path_a)
        icon_b = ui.image(path_b)
        ui.label(:pic, image: icon_a)
      end
      session.run_async
      session.app.update

      pic_path = session[:pic].path
      assert_equal icon_a.name, session.app.command(pic_path, :cget, '-image')

      session[:pic].configure(image: icon_b)

      assert_equal icon_b.name, session.app.command(pic_path, :cget, '-image')

      session.app.destroy
    end
  end

  tk_test "an image declared via ui.image should stay alive (retained on the session) for as long as the widget referencing it exists" do
    require 'teek/ui'
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.png')
      seed = Teek::Photo.new(app, width: 4, height: 4)
      seed.put_block(([0, 0, 0, 255].pack('CCCC')) * 16, 4, 4)
      app.tcl_eval("#{seed.name} write {#{path}} -format png")
      seed.delete

      session = Teek::UI.app(title: 'Image Test') do |ui|
        ui.label(:pic, image: ui.image(path))
      end
      session.run_async
      session.app.update

      # nothing outside the session holds a reference to the Image -
      # only Session#images does. Forcing a GC pass here is the whole
      # point: if the session weren't retaining it, this would be the
      # moment the image gets collected (and the widget's -image would
      # go stale/broken).
      GC.start

      assert_equal 1, session.images.length
      image = session.images.first
      assert_equal 'photo', session.app.tcl_eval("image type #{image.name}")
      assert_equal image.name, session.app.command(session[:pic].path, :cget, '-image')

      session.app.destroy
    end
  end
end
