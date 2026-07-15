# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/document'
require 'teek/ui/realizer'
require 'teek/ui/event_binding'

# Headless coverage of the lazy: true skip/on-demand-realize mechanism
# itself, isolated from Handle (which stays a thin, private wrapper
# around this - see test_screens_realtk.rb/test_modal_stack_realtk.rb
# for the real-Tk, public-facing behavior through ui.screens/ui.modal)
# and from real Tk entirely - built by hand against Document/Node/
# Realizer's own public API, using the shared FakeApp (support/fake_app.rb)
# to record what Realizer would have created, the same way test_screens.rb
# does for Screens' own reveal/conceal calls.
class TestLazyRealize < Minitest::Test
  def build_host_and_picker(picker_children: [])
    document = Teek::UI::Document.new
    host = document.create(type: :panel, name: :host)
    document.root.add_child(host)
    picker = document.create(type: :panel, name: :picker)
    picker.lazy = true
    host.add_child(picker)
    picker_children.each { |child| picker.add_child(child) }
    [document, host, picker]
  end

  def test_a_lazy_node_is_not_created_by_the_initial_realize
    document, _host, picker = build_host_and_picker
    app = FakeApp.new

    Teek::UI::Realizer.new(app, document).realize

    assert_nil picker.realized
    refute app.calls.any? { |(args, _)| args.include?('.host.picker') }
  end

  def test_a_lazy_nodes_own_children_are_also_skipped_by_the_initial_realize
    document, _host, picker = build_host_and_picker
    load_node = document.create(type: :button, name: :load, opts: { text: 'Load' })
    picker.add_child(load_node)
    app = FakeApp.new

    Teek::UI::Realizer.new(app, document).realize

    assert_nil load_node.realized
    refute app.calls.any? { |(args, _)| args.include?('.host.picker.load') }
  end

  def test_a_non_lazy_sibling_still_realizes_normally_next_to_a_lazy_one
    document, host, _picker = build_host_and_picker
    go = document.create(type: :button, name: :go, opts: { text: 'Go' })
    host.add_child(go)
    app = FakeApp.new

    Teek::UI::Realizer.new(app, document).realize

    refute_nil go.realized
    assert_equal '.host.go', go.realized.path
    assert app.calls.any? { |(args, _)| args.include?('.host.go') }
  end

  def test_arrange_children_does_not_choke_on_a_still_unrealized_lazy_sibling
    document, host, _picker = build_host_and_picker
    go = document.create(type: :button, name: :go, opts: { text: 'Go' })
    host.add_child(go)
    app = FakeApp.new

    # link() (which arrange_children is part of) walks the WHOLE tree
    # after create finishes - reaching this line without a NoMethodError
    # on a nil .realized for the still-lazy :picker sibling IS the
    # assertion (see Realizer#arrange_children's own lazy-aware filter).
    Teek::UI::Realizer.new(app, document).realize

    assert app.calls.any? { |(args, kwargs)| args == [:pack, '.host.go'] || (args.first == :pack && kwargs.empty?) }
  end

  def test_realize_subtree_realizes_a_lazy_node_and_its_own_children_on_demand
    document, host, picker = build_host_and_picker
    load_node = document.create(type: :button, name: :load, opts: { text: 'Load' })
    picker.add_child(load_node)
    app = FakeApp.new
    Teek::UI::Realizer.new(app, document).realize

    Teek::UI::Realizer.new(app, document).realize_subtree(picker, host)

    refute_nil picker.realized
    assert_equal '.host.picker', picker.realized.path
    refute_nil load_node.realized
    assert_equal '.host.picker.load', load_node.realized.path
    assert app.calls.any? { |(args, _)| args.include?('.host.picker') }
    assert app.calls.any? { |(args, _)| args.include?('.host.picker.load') }
  end

  def test_realize_subtree_wires_events_queued_before_realize
    document, host, picker = build_host_and_picker
    fired = false
    picker.events << Teek::UI::EventBinding.new(event: '<Button-1>', handler: -> { fired = true }, subs: [])
    app = FakeApp.new
    Teek::UI::Realizer.new(app, document).realize

    Teek::UI::Realizer.new(app, document).realize_subtree(picker, host)

    bound = app.binds.find { |b| b[:path] == '.host.picker' && b[:event] == '<Button-1>' }
    refute_nil bound, "the event queued on the lazy node before realize should get wired once it's realized"
    bound[:block].call
    assert fired
  end

  def test_a_later_arrange_children_call_picks_up_a_now_realized_former_lazy_sibling
    document, host, picker = build_host_and_picker
    app = FakeApp.new
    Teek::UI::Realizer.new(app, document).realize
    Teek::UI::Realizer.new(app, document).realize_subtree(picker, host)
    app.calls.clear

    # mirrors Session#add adding a further sibling to :host later - its
    # own realize_subtree re-arranges ALL of host's children, which by
    # now includes the no-longer-lazy :picker (see Realizer#arrange_children's
    # "lazy? && !realized" - not bare "lazy?" - filter).
    another = document.create(type: :button, name: :another, opts: { text: 'Another' })
    host.add_child(another)
    Teek::UI::Realizer.new(app, document).realize_subtree(another, host)

    assert app.calls.any? { |(args, _)| args.include?('.host.picker') },
      "the now-realized :picker should be re-arranged alongside the new sibling, not skipped forever"
  end
end
