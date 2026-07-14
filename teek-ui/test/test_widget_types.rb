# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/widget_types'
require 'teek/ui/widget_dsl'

class TestWidgetTypes < Minitest::Test
  # type -> [tk_command, bind_option, natively_scrollable?] for every leaf
  # migrated off the legacy LEAF_TYPES/TK_COMMANDS/BIND_OPTIONS lists -
  # matches the original hardcoded mapping exactly (this table is the
  # migration's own regression check, not a copy of production code).
  MIGRATED_LEAVES = {
    text_box: ['ttk::entry', :textvariable, false],
    text_area: ['text', nil, true],
    label: ['ttk::label', :textvariable, false],
    button: ['ttk::button', nil, false],
    checkbox: ['ttk::checkbutton', :variable, false],
    radio: ['ttk::radiobutton', nil, false],
    slider: ['ttk::scale', :variable, false],
    dropdown: ['ttk::combobox', :textvariable, false],
    number_box: ['ttk::spinbox', :textvariable, false],
    list: ['listbox', nil, true],
    table: ['ttk::treeview', nil, true],
    tree: ['ttk::treeview', nil, true],
    progress: ['ttk::progressbar', :variable, false],
  }.freeze

  def test_every_migrated_leaf_is_registered_with_the_right_metadata
    MIGRATED_LEAVES.each do |type, (tk_command, bind_option, natively_scrollable)|
      widget_type = Teek::UI::WidgetTypes.for_type(type)

      refute_nil widget_type, "expected :#{type} to be registered as a WidgetType"
      assert widget_type.leaf?, ":#{type} should be a leaf"
      assert_equal tk_command, widget_type.tk_command, ":#{type} tk_command"
      bind_option.nil? ? assert_nil(widget_type.bind_option, ":#{type} bind_option") : assert_equal(bind_option, widget_type.bind_option, ":#{type} bind_option")
      assert_equal natively_scrollable, widget_type.natively_scrollable?, ":#{type} natively_scrollable?"
    end
  end

  def test_leaf_types_no_longer_exists_now_that_every_leaf_has_migrated
    refute Teek::UI::WidgetDSL.const_defined?(:LEAF_TYPES)
  end

  def test_bind_options_no_longer_exists_now_that_every_bindable_leaf_has_migrated
    refute Teek::UI::WidgetDSL.const_defined?(:BIND_OPTIONS)
  end

  def test_scrollable_types_shrinks_to_just_the_unmigrated_container_remainder
    assert_equal [:canvas], Teek::UI::WidgetDSL::SCROLLABLE_TYPES
  end

  def test_divider_is_registered_as_a_built_in
    widget_type = Teek::UI::WidgetTypes.for_type(:divider)

    refute_nil widget_type
    assert_equal :divider, widget_type.type
    assert_equal 'ttk::separator', widget_type.tk_command
  end

  def test_for_type_returns_nil_for_an_unregistered_type
    assert_nil Teek::UI::WidgetTypes.for_type(:__never_registered__)
  end

  def test_for_type_accepts_a_string_type_too
    assert_equal Teek::UI::WidgetTypes.for_type(:divider), Teek::UI::WidgetTypes.for_type('divider')
  end

  def test_register_raises_on_a_duplicate_type
    Teek::UI::WidgetTypes.register(Teek::UI::WidgetType.new(type: :__test_widget_types_dup__, tk_command: 'ttk::label'))

    error = assert_raises(ArgumentError) {
      Teek::UI::WidgetTypes.register(Teek::UI::WidgetType.new(type: :__test_widget_types_dup__, tk_command: 'ttk::label'))
    }
    assert_match(/already registered/, error.message)
  end

  def test_each_enumerates_every_registered_type_including_divider
    types = Teek::UI::WidgetTypes.each.map(&:type)

    assert_includes types, :divider
  end

  def test_on_register_replays_every_already_registered_type
    seen = []
    Teek::UI::WidgetTypes.on_register { |widget_type| seen << widget_type.type }

    assert_includes seen, :divider
  end

  def test_on_register_also_fires_for_a_type_registered_afterward
    seen = []
    Teek::UI::WidgetTypes.on_register { |widget_type| seen << widget_type.type }

    Teek::UI::WidgetTypes.register(Teek::UI::WidgetType.new(type: :__test_widget_types_late__, tk_command: 'ttk::label'))

    assert_includes seen, :__test_widget_types_late__
  end

  def test_register_forwards_a_composed_validator_into_widget_validators
    validator = ->(_node, _parent, _document, errors) { errors << 'composed validator ran' }

    Teek::UI::WidgetTypes.register(
      Teek::UI::WidgetType.new(type: :__test_widget_types_validated__, tk_command: 'ttk::label', validator: validator)
    )

    dispatched = Teek::UI::WidgetValidators.for_type(:__test_widget_types_validated__)
    errors = []
    dispatched.each { |v| v.call(nil, nil, nil, errors) }

    assert_equal ['composed validator ran'], errors
  end

  def test_a_type_with_no_validator_forwards_nothing
    assert_empty Teek::UI::WidgetValidators.for_type(:divider)
  end

  def test_leaf_defaults
    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_leaf_defaults__, tk_command: 'ttk::label')

    assert widget_type.leaf?
    refute widget_type.container?
    refute widget_type.natively_scrollable?
    assert_nil widget_type.bind_option
    assert_nil widget_type.validator
  end

  def test_leaf_default_dsl_defines_a_method_that_calls_append_leaf
    calls = []
    fake_module = Class.new {
      define_method(:append_leaf) { |type, name, opts| calls << [type, name, opts] }
    }.new

    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_dsl__, tk_command: 'ttk::label')
    widget_type.define_dsl_method!(fake_module.singleton_class)
    fake_module.__test_widget_type_dsl__(:thing, text: 'Hi')

    assert_equal [[:__test_widget_type_dsl__, :thing, { text: 'Hi' }]], calls
  end

  def test_container_leaf_false_uses_append_container
    calls = []
    fake_module = Class.new {
      define_method(:append_container) { |type, name, opts, &block| calls << [type, name, opts, block] }
    }.new

    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_container_dsl__, tk_command: 'ttk::frame', leaf: false)
    widget_type.define_dsl_method!(fake_module.singleton_class)
    fake_module.__test_widget_type_container_dsl__(:thing)

    assert_equal :__test_widget_type_container_dsl__, calls.first[0]
    assert_equal :thing, calls.first[1]
  end

  def test_post_create_defaults_to_a_no_op
    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_no_post_create__, tk_command: 'ttk::label')

    assert_nil widget_type.post_create(:app, :node, :path)
  end

  def test_post_create_runs_the_given_hook
    calls = []
    widget_type = Teek::UI::WidgetType.new(
      type: :__test_widget_type_post_create__, tk_command: 'ttk::label',
      post_create: ->(app, node, path) { calls << [app, node, path] }
    )

    widget_type.post_create(:app, :node, :path)

    assert_equal [[:app, :node, :path]], calls
  end
end
