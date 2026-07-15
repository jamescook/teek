# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/tree_inspector'
require 'teek/ui/document'
require 'teek/ui/session'

# TreeInspector only ever calls #root and #subscribe on whatever it's
# given - these two minimal doubles exist to prove that's genuinely true
# (it works against ANY object shaped like this, not just an instance of
# Teek::UI::Document/Node), not merely that it's convenient to unit test
# through the real classes.
FakeInspectorNode = Struct.new(:type, :name, :opts, :children) do
  def display_name
    name ? "#{type}(:#{name})" : type.to_s
  end
end

FakeInspectorDocument = Struct.new(:root) do
  def initialize(root)
    super
    @listeners = Hash.new { |h, k| h[k] = [] }
  end

  def subscribe(event, &block)
    @listeners[event] << block
  end

  def notify(event, *args)
    @listeners[event].each { |listener| listener.call(*args) }
  end
end

class TestTreeInspector < Minitest::Test
  def test_to_s_and_log_work_against_a_fake_document_not_the_real_teek_ui_one
    button = FakeInspectorNode.new(:button, nil, { text: 'Go' }, [])
    root = FakeInspectorNode.new(:root, nil, {}, [button])
    document = FakeInspectorDocument.new(root)

    inspector = Teek::UI::TreeInspector.new(document, trace: true)
    document.notify(:append, root, button)

    assert_equal "root\n└─ button \"Go\"", inspector.to_s
    assert_equal 1, inspector.log.length
    assert_equal :append, inspector.log.first.action
    assert_same button, inspector.log.first.node
  end

  def test_to_s_renders_the_example_shape
    document = Teek::UI::Document.new
    column = document.root.add_child(document.create(type: :column))
    column.add_child(document.create(type: :label, opts: { text: 'Title' }))
    row = column.add_child(document.create(type: :row))
    row.add_child(document.create(type: :button, opts: { text: 'OK' }))
    row.add_child(document.create(type: :button, opts: { text: 'Cancel' }))
    column.add_child(document.create(type: :label, opts: { text: 'Footer' }))

    expected = <<~TREE.chomp
      root
      └─ column
         ├─ label "Title"
         ├─ row
         │  ├─ button "OK"
         │  └─ button "Cancel"
         └─ label "Footer"
    TREE

    assert_equal expected, Teek::UI::TreeInspector.new(document).to_s
  end

  def test_to_s_on_an_empty_document_is_just_root
    document = Teek::UI::Document.new

    assert_equal 'root', Teek::UI::TreeInspector.new(document).to_s
  end

  def test_to_s_shows_a_name_alongside_the_type
    document = Teek::UI::Document.new
    document.root.add_child(document.create(type: :column, name: :ctrl))

    assert_equal "root\n└─ column(:ctrl)", Teek::UI::TreeInspector.new(document).to_s
  end

  def test_to_s_prefers_text_over_label_when_a_node_somehow_has_both
    document = Teek::UI::Document.new
    document.root.add_child(document.create(type: :button, opts: { text: 'OK', label: 'ignored' }))

    assert_equal "root\n└─ button \"OK\"", Teek::UI::TreeInspector.new(document).to_s
  end

  def test_to_s_falls_back_to_label_for_a_menu_item_shaped_node
    document = Teek::UI::Document.new
    document.root.add_child(document.create(type: :menu_item, opts: { label: 'Open' }))

    assert_equal "root\n└─ menu_item \"Open\"", Teek::UI::TreeInspector.new(document).to_s
  end

  def test_to_s_reflects_the_trees_current_shape_when_called_again_later
    document = Teek::UI::Document.new
    inspector = Teek::UI::TreeInspector.new(document)

    assert_equal 'root', inspector.to_s

    document.root.add_child(document.create(type: :button, opts: { text: 'Go' }))

    assert_equal "root\n└─ button \"Go\"", inspector.to_s
  end

  def test_print_tree_writes_to_s_to_stdout
    document = Teek::UI::Document.new
    document.root.add_child(document.create(type: :button, opts: { text: 'Go' }))
    inspector = Teek::UI::TreeInspector.new(document)

    out, = capture_io { inspector.print_tree }

    assert_equal "#{inspector}\n", out
  end

  def test_log_is_empty_without_trace_true
    document = Teek::UI::Document.new
    inspector = Teek::UI::TreeInspector.new(document)

    document.root.add_child(document.create(type: :button))

    assert_equal [], inspector.log
  end

  def test_log_records_append_events_once_tracing
    document = Teek::UI::Document.new
    inspector = Teek::UI::TreeInspector.new(document, trace: true)
    parent = document.create(type: :column, name: :ctrl)
    child = document.create(type: :button, opts: { text: 'Go' })

    parent.add_child(child)

    assert_equal 1, inspector.log.length
    event = inspector.log.first
    assert_equal :append, event.action
    assert_same child, event.node
    assert_equal 'column(:ctrl)', event.path
  end

  def test_log_records_push_and_pop_events_once_tracing_through_the_real_builder
    session = Teek::UI::Session.new(title: 'Tree Inspector Test')
    inspector = Teek::UI::TreeInspector.new(session.document, trace: true)

    session.column(:ctrl) { |c| c.row(:speed_row) { } }

    actions = inspector.log.map(&:action)
    assert_equal %i[append push append push pop pop], actions
    assert_equal 'root', inspector.log[0].path, "column appended under the (unnamed) root"
    assert_equal 'column(:ctrl)', inspector.log[1].path, "pushing column - path now includes it"
    assert_equal 'column(:ctrl)', inspector.log[2].path, "row appended under column"
    assert_equal 'column(:ctrl) > row(:speed_row)', inspector.log[3].path, "pushing row - path now includes it too"
  end

  def test_two_inspectors_on_the_same_document_are_independent
    document = Teek::UI::Document.new
    tracing = Teek::UI::TreeInspector.new(document, trace: true)
    not_tracing = Teek::UI::TreeInspector.new(document)

    document.root.add_child(document.create(type: :button))

    refute_empty tracing.log
    assert_empty not_tracing.log
  end

  def test_event_to_s_is_readable_for_each_action
    document = Teek::UI::Document.new
    inspector = Teek::UI::TreeInspector.new(document, trace: true)
    parent = document.create(type: :column)
    child = document.create(type: :button)

    document.notify(:push, parent, 'column')
    parent.add_child(child)
    document.notify(:pop, parent, 'column')

    push_s, append_s, pop_s = inspector.log.map(&:to_s)
    assert_match(/column/, push_s)
    assert_match(/button/, append_s)
    assert_match(/column/, pop_s)
  end
end
