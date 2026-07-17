# frozen_string_literal: true

# Tests for Teek::Photo's GC-finalizer-based image reclamation and the
# generic #command passthrough - see also test_photo.rb for the rest of
# the Photo API.
#
# A Tk photo image is a named, global, shareable resource - Tk itself
# never frees it when the Ruby-side wrapper is dropped. Photo now
# registers a finalizer that releases the underlying image once nothing
# in Ruby references the wrapper anymore, the same contract as File or
# Socket: keep the Photo object alive for as long as you need the
# image. If only the image *name* is kept around (e.g. passed into a
# widget's -image) and the wrapper itself is dropped, the image can be
# reclaimed out from under that reference - that's an accepted
# tradeoff, not a bug; Tk just shows a broken image, it doesn't crash.
#
# Finalizers can run on any thread, so the delete is routed through
# Interp#queue_for_main (fire-and-forget) rather than #tcl_eval
# directly, which would block on a cross-thread queue wait if called
# from a background thread - risky from inside a GC finalizer.
#
# What these tests don't do: assert that GC.start actually collects a
# dropped Photo and fires its finalizer. That's reliable in isolation,
# but this suite runs many tests through one shared, persistent worker
# process (see tk_test_helper.rb) - MRI's GC conservatively scans the
# whole C stack, and stack/register content left over from whichever
# test happened to run first is enough to occasionally retain a
# reference that wouldn't be there standalone, so a GC-timing assertion
# here would be genuinely flaky, not just theoretically so (confirmed:
# 5/5 clean in isolation, failed 2/3 runs in this file). Instead,
# {test_finalizer_deletes_the_image_it_was_built_for} calls the
# finalizer proc directly - that's the part of the mechanism teek
# controls and should prove; that Ruby's GC eventually invokes a
# registered finalizer is ObjectSpace's own documented contract, not
# something this suite needs to re-verify.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestPhotoGC < Minitest::Test
  include TeekTestHelper

  tk_test "Interp#queue_for_main should run its block on the main Tcl thread" do
    ran_on_main = nil
    app.interp.queue_for_main(proc { ran_on_main = app.interp.on_main_thread? })
    app.update

    assert_equal true, ran_on_main, "queued block should have run on the main thread"
  end

  tk_test "the proc Photo.finalizer_for builds should delete the named image when called" do
    app.command(:image, :create, :photo, 'teek_test_finalizer_target', width: 5, height: 5)
    assert_includes app.split_list(app.tcl_eval('image names')), 'teek_test_finalizer_target'

    Teek::Photo.finalizer_for('teek_test_finalizer_target', app).call
    app.update

    refute_includes app.split_list(app.tcl_eval('image names')), 'teek_test_finalizer_target',
      "the finalizer proc should have deleted the image"
  end

  tk_test "explicitly deleting a Photo should cancel its finalizer, not just the image" do
    p = Teek::Photo.new(app, width: 5, height: 5)
    name = p.name
    p.delete

    # Recreate a *different* photo at the same name before a stale
    # finalizer could fire - if #delete didn't cancel it, a later GC
    # could delete this unrelated image out from under it.
    p2 = Teek::Photo.new(app, name: name, width: 5, height: 5)
    GC.start
    app.update

    assert p2.exist?, "a stale finalizer must not delete a same-named image created after explicit delete"
    p2.delete
  end

  tk_test "Photo#command should support arbitrary photo subcommands like copy" do
    source = Teek::Photo.new(app, width: 40, height: 20)
    red = ([255, 0, 0, 255].pack('CCCC')) * (40 * 20)
    source.put_block(red, 40, 20)

    dest = Teek::Photo.new(app, name: 'teek_test_copy_dest')
    dest.command(:copy, source, subsample: 4)

    w, h = dest.get_size
    assert_equal 10, w
    assert_equal 5, h

    source.delete
    dest.delete
  end

  tk_test "Photo.new(file:) + #command copy subsample should produce a correctly-sized image" do
    require 'tmpdir'
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.png')
      seed = Teek::Photo.new(app, width: 80, height: 40)
      blue = ([0, 0, 255, 255].pack('CCCC')) * (80 * 40)
      seed.put_block(blue, 80, 40)
      app.tcl_eval("#{seed.name} write {#{path}} -format png")
      seed.delete

      loaded = Teek::Photo.new(app, file: path)
      w, h = loaded.get_size
      assert_equal 80, w
      assert_equal 40, h

      small = Teek::Photo.new(app)
      small.command(:copy, loaded, subsample: 2)
      sw, sh = small.get_size
      assert_equal 40, sw
      assert_equal 20, sh

      loaded.delete
      small.delete
    end
  end
end
