# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Handle#text_content's rich text API (TextContent) - a companion
# object, not methods bolted onto Handle; Tk index syntax passed
# through verbatim; friendly names primary with Tk-named aliases;
# leak-safe format/tag event bindings; the read-only footgun
# transparently absorbed.
class TestTextContent < Minitest::Test
  include TeekTestHelper

  tk_test "text_content should raise before realize, matching every other realize-only accessor" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }

    assert_raises(Teek::UI::NotRealizedError) { session[:notes].text_content }
  end

  tk_test "text_content should raise a clear error on a widget that isn't a text_area" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.button(:go, text: 'Go') }
    session.run_async

    error = assert_raises(ArgumentError) { session[:go].text_content }
    assert_match(/text_area/i, error.message)

    session.app.destroy
  end

  # -- Content -----------------------------------------------------------

  tk_test "insert should add text at an index, get should read it back" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content

    text.insert('1.0', 'hello world')

    assert_equal 'hello', text.get('1.0', '1.5')
    assert_equal 'hello world', text.value

    session.app.destroy
  end

  tk_test "delete should remove a range" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    text.insert('1.0', 'hello world')

    text.delete('1.0', '1.6')

    assert_equal 'world', text.value

    session.app.destroy
  end

  tk_test "replace should atomically swap a range for new text" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    text.insert('1.0', 'hello world')

    text.replace('1.0', '1.5', 'goodbye')

    assert_equal 'goodbye world', text.value

    session.app.destroy
  end

  tk_test "value= should replace the entire buffer's content" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    text.insert('1.0', 'old content')

    text.value = 'new content'

    assert_equal 'new content', text.value

    session.app.destroy
  end

  tk_test "clear should empty the whole buffer" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    text.insert('1.0', 'something')

    text.clear

    assert_equal '', text.value

    session.app.destroy
  end

  tk_test ":end and :cursor should resolve to Tk's own end/insert indices" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content

    text.insert(:end, 'first')
    text.insert(:end, ' second')

    assert_equal 'first second', text.value
    assert_equal text.index(:end), text.index('end')

    session.app.destroy
  end

  # -- Read-only footgun ---------------------------------------------------

  tk_test "insert/delete/replace/value=/clear should work on a read-only widget and leave it read-only after" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:log, state: :disabled) }
    session.run_async
    text = session[:log].text_content
    assert text.read_only, "should have started read-only, matching state: :disabled"

    text.insert(:end, 'line one\n')
    assert text.read_only, "should still be read-only after insert"

    text.value = 'replaced'
    assert text.read_only, "should still be read-only after value="

    text.clear
    assert text.read_only, "should still be read-only after clear"
    assert_equal '', text.value

    session.app.destroy
  end

  tk_test "read_only/read_only= should read and drive the widget's own -state" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    refute text.read_only, "should start editable by default"

    text.read_only = true
    assert text.read_only

    text.read_only = false
    refute text.read_only

    session.app.destroy
  end

  # -- Formats (Tk tags) ---------------------------------------------------

  tk_test "format should define display properties, apply_format should apply them to a range" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:code) }
    session.run_async
    text = session[:code].text_content
    text.insert(:end, 'errorline')

    text.format(:error, foreground: 'red')
    text.apply_format(:error, '1.0', '1.5')

    assert_equal 'red', session.app.command(session[:code].path, :tag, :cget, :error, '-foreground')
    assert_equal ['1.0', '1.5'], text.format_ranges(:error)

    session.app.destroy
  end

  tk_test "clear_format should remove the format from a range but keep the definition applyable elsewhere" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:code) }
    session.run_async
    text = session[:code].text_content
    text.insert(:end, 'abcdef')
    text.format(:hl, foreground: 'red')
    text.apply_format(:hl, '1.0', '1.3')

    text.clear_format(:hl, '1.0', '1.3')

    assert_equal [], text.format_ranges(:hl)

    text.apply_format(:hl, '1.3', '1.6')
    assert_equal ['1.3', '1.6'], text.format_ranges(:hl)

    session.app.destroy
  end

  tk_test "delete_format should remove the format definition and every range it was applied to" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:code) }
    session.run_async
    text = session[:code].text_content
    text.insert(:end, 'abcdef')
    text.format(:hl, foreground: 'red')
    text.apply_format(:hl, '1.0', '1.3')

    text.delete_format(:hl)

    names = session.app.split_list(session.app.command(session[:code].path, :tag, :names))
    refute_includes names, 'hl'

    session.app.destroy
  end

  tk_test "tag_configure/tag_add/tag_remove/tag_delete/tag_ranges should alias the friendly names" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:code) }
    session.run_async
    text = session[:code].text_content
    text.insert(:end, 'abcdef')

    text.tag_configure(:hl, foreground: 'blue')
    text.tag_add(:hl, '1.0', '1.3')
    assert_equal ['1.0', '1.3'], text.tag_ranges(:hl)

    text.tag_remove(:hl, '1.0', '1.3')
    assert_equal [], text.tag_ranges(:hl)

    text.tag_add(:hl, '1.0', '1.3')
    text.tag_delete(:hl)
    names = session.app.split_list(session.app.command(session[:code].path, :tag, :names))
    refute_includes names, 'hl'

    session.app.destroy
  end

  # -- Leak-safe format/tag event bindings ---------------------------------

  tk_test "on_format_click should fire when text carrying that format is clicked" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:log) }
    session.run_async
    session.app.update
    text = session[:log].text_content
    text.insert(:end, 'click me')
    text.format(:link, foreground: 'blue')
    text.apply_format(:link, '1.0', '1.8')
    session.app.update

    clicked = false
    text.on_format_click(:link) { clicked = true }

    # tag bind hit-tests by pixel position, unlike a widget-level bind -
    # query the real bbox of a character inside the tagged range rather
    # than guess a pixel offset that may land in padding/margin instead.
    bbox = session.app.split_list(session.app.command(session[:log].path, :bbox, '1.2')).map(&:to_i)
    x, y = bbox[0] + 2, bbox[1] + 2
    session.app.tcl_eval("focus -force #{session[:log].path}")
    session.app.update
    # Tk's "current tag under the pointer" is motion-tracked, same as
    # canvas's own "current item" - a bare synthetic Button-1 with no
    # prior Motion to that position never updates it, so the click
    # dispatches as if nothing were under the pointer.
    session.app.tcl_eval("event generate #{session[:log].path} <Motion> -x #{x} -y #{y}")
    session.app.update
    session.app.tcl_eval("event generate #{session[:log].path} <Button-1> -x #{x} -y #{y}")

    assert wait_until { clicked }, "on_format_click did not fire"

    session.app.destroy
  end

  tk_test "removing a formatted range's callback should release it, not leak, proving this routes through app.command (not tcl_eval)" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:log) }
    session.run_async
    text = session[:log].text_content
    text.insert(:end, 'click me')
    text.format(:link, foreground: 'blue')
    text.apply_format(:link, '1.0', '1.8')

    baseline = session.debug_info[:tag_binds] || 0
    text.on_format_click(:link) { }
    assert_equal baseline + 1, session.debug_info[:tag_binds]

    # Rebinding the SAME tag+event replaces (not stacks) the callback -
    # Tk's own tag bind semantics - so the count should stay at +1,
    # never climb, across repeated rebinds.
    3.times { text.on_format_click(:link) { } }
    assert_equal baseline + 1, session.debug_info[:tag_binds],
      "rebinding the same format+event should replace, not accumulate"

    text.delete_format(:link)
    session.app.update

    assert_equal baseline, session.debug_info[:tag_binds] || 0,
      "deleting the format should release its callback via the leak-safe tag_bind reconcile"

    session.app.destroy
  end

  tk_test "on_format should accept an arbitrary Tk event pattern, auto-wrapped in angle brackets" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:log) }
    session.run_async
    session.app.update
    text = session[:log].text_content
    text.insert(:end, 'ctrl click me')
    text.format(:special, foreground: 'green')
    text.apply_format(:special, '1.0', '1.13')
    session.app.update

    fired = false
    # Double-/Triple-/Quadruple- click patterns can't be synthetically
    # generated via `event generate` (Tk only synthesizes those from
    # real, timed events) - a modifier+button combo like this one can be.
    text.on_format('special', 'Control-Button-1') { fired = true }

    bbox = session.app.split_list(session.app.command(session[:log].path, :bbox, '1.2')).map(&:to_i)
    x, y = bbox[0] + 2, bbox[1] + 2
    session.app.tcl_eval("focus -force #{session[:log].path}")
    session.app.update
    session.app.tcl_eval("event generate #{session[:log].path} <Motion> -x #{x} -y #{y}")
    session.app.update
    session.app.tcl_eval("event generate #{session[:log].path} <Control-Button-1> -x #{x} -y #{y}")

    assert wait_until { fired }, "on_format with a custom event pattern did not fire"

    session.app.destroy
  end

  # -- Markers -------------------------------------------------------------

  tk_test "add_marker/remove_marker/markers should manage named floating positions" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    text.insert(:end, 'hello world')

    text.add_marker(:checkpoint, at: '1.6')

    assert_includes text.markers, 'checkpoint'
    assert_equal '1.6', text.index(:checkpoint)

    text.remove_marker(:checkpoint)
    refute_includes text.markers, 'checkpoint'

    session.app.destroy
  end

  tk_test "mark_gravity should read the default and accept an explicit direction" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    text.insert(:end, 'hello world')
    text.add_marker(:checkpoint, at: '1.3')

    assert_equal 'right', text.mark_gravity(:checkpoint)

    text.mark_gravity(:checkpoint, :left)
    assert_equal 'left', text.mark_gravity(:checkpoint)

    session.app.destroy
  end

  # -- Search ----------------------------------------------------------------

  tk_test "search should return the matching index, or nil if not found" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    text.insert(:end, 'the quick brown fox')

    assert_equal '1.4', text.search('quick', from: '1.0')
    assert_nil text.search('nonexistent', from: '1.0')

    session.app.destroy
  end

  tk_test "search's backwards/regexp/nocase switches should all forward correctly" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    text.insert(:end, 'FOO bar foo baz')

    assert_equal '1.8', text.search('foo', from: :end, to: '1.0', backwards: true)
    assert_equal '1.0', text.search('F[A-Z]{2}', from: '1.0', regexp: true)
    assert_equal '1.0', text.search('foo', from: '1.0', nocase: true)

    session.app.destroy
  end

  # -- View / cursor / state --------------------------------------------------

  tk_test "scroll_to (and its see alias) should not raise against a real index" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes, height: 3) }
    session.run_async
    text = session[:notes].text_content
    20.times { |i| text.insert(:end, "line #{i}\n") }

    text.scroll_to('10.0')
    text.see('1.0')

    session.app.destroy
  end

  tk_test "index should resolve any index expression to canonical line.char form" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    text.insert(:end, "line one\nline two\n")

    assert_equal '2.0', text.index('2.0')
    assert_equal '1.4', text.index('1.0 +4 chars')

    session.app.destroy
  end

  tk_test "cursor should read and move the text insertion point" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    text.insert(:end, 'hello world')

    text.cursor = '1.5'

    assert_equal '1.5', text.cursor
    assert_equal text.index(:cursor), text.cursor

    session.app.destroy
  end

  # -- Embedded images ---------------------------------------------------------

  tk_test "insert_image should embed a ui.image inline in the text flow" do
    require 'teek/ui'
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.png')
      seed = Teek::Photo.new(app, width: 4, height: 4)
      seed.put_block(([0, 0, 0, 255].pack('CCCC')) * 16, 4, 4)
      app.tcl_eval("#{seed.name} write {#{path}} -format png")
      seed.delete

      icon = nil
      session = Teek::UI.app(title: 'Text Content Test') { |ui|
        icon = ui.image(path)
        ui.text_area(:notes)
      }
      session.run_async
      text = session[:notes].text_content
      text.insert(:end, 'before ')

      text.insert_image(:end, image: icon)
      text.insert(:end, ' after')

      dump = session.app.command(session[:notes].path, :dump, '-image', '1.0', 'end')
      assert_match(/#{Regexp.escape(icon.name)}/, dump)

      session.app.destroy
    end
  end

  tk_test "insert_image should transparently lift and restore read-only state, same as the other mutators" do
    require 'teek/ui'
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.png')
      seed = Teek::Photo.new(app, width: 4, height: 4)
      seed.put_block(([0, 0, 0, 255].pack('CCCC')) * 16, 4, 4)
      app.tcl_eval("#{seed.name} write {#{path}} -format png")
      seed.delete

      icon = nil
      session = Teek::UI.app(title: 'Text Content Test') { |ui|
        icon = ui.image(path)
        ui.text_area(:notes, state: :disabled)
      }
      session.run_async
      text = session[:notes].text_content

      text.insert_image(:end, image: icon)

      assert text.read_only, "should still be read-only after insert_image"

      session.app.destroy
    end
  end

  # -- Driving use cases ---------------------------------------------------

  tk_test "driving use case: a syntax-highlighted code/log view via format + apply_format" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:code) }
    session.run_async
    text = session[:code].text_content

    text.insert(:end, "def hello\n  puts 'hi'\nend\n")
    text.format(:keyword, foreground: 'purple', font: ['Courier', 10, :bold])
    text.apply_format(:keyword, '1.0', '1.3')
    text.apply_format(:keyword, '3.0', '3.3')

    assert_equal ['1.0', '1.3', '3.0', '3.3'], text.format_ranges(:keyword)

    session.app.destroy
  end

  tk_test "driving use case: search-and-replace via search + replace" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:notes) }
    session.run_async
    text = session[:notes].text_content
    text.insert(:end, 'the cat sat on the mat')

    loop do
      found = text.search('the', from: '1.0')
      break unless found

      text.replace(found, "#{found} +3 chars", 'THE')
      # advance search past the just-replaced word next iteration
      break if text.search('the', from: "#{found} +3 chars").nil?
    end

    assert_equal 'THE cat sat on THE mat', text.value

    session.app.destroy
  end

  tk_test "driving use case: an appending, auto-scrolling, read-only log pane" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Text Content Test') { |ui| ui.text_area(:log, height: 3, state: :disabled) }
    session.run_async
    text = session[:log].text_content

    5.times { |i| text.insert(:end, "log line #{i}\n") }
    text.scroll_to(:end)

    assert text.read_only, "the log pane should still be read-only after appending"
    assert_match(/log line 4/, text.value)

    session.app.destroy
  end

  tk_test "driving use case: inline images via insert_image" do
    require 'teek/ui'
    require 'tmpdir'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.png')
      seed = Teek::Photo.new(app, width: 4, height: 4)
      seed.put_block(([0, 0, 0, 255].pack('CCCC')) * 16, 4, 4)
      app.tcl_eval("#{seed.name} write {#{path}} -format png")
      seed.delete

      icon = nil
      session = Teek::UI.app(title: 'Text Content Test') { |ui|
        icon = ui.image(path)
        ui.text_area(:notes)
      }
      session.run_async
      text = session[:notes].text_content

      text.insert(:end, 'Logo: ')
      text.insert_image(:end, image: icon)

      dump = session.app.command(session[:notes].path, :dump, '-image', '1.0', 'end')
      assert_match(/#{Regexp.escape(icon.name)}/, dump)

      session.app.destroy
    end
  end
end
