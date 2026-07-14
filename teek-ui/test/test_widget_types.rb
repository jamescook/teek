# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui'
require 'teek/ui/widget_types'
require 'teek/ui/widget_dsl'

class TestWidgetTypes < Minitest::Test
  # type -> [tk_command, bind_option, natively_scrollable?] for every leaf
  # widget type - a regression check independent of production code, not
  # a copy of it.
  LEAF_METADATA = {
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

  def test_every_leaf_widget_type_is_registered_with_the_right_metadata
    LEAF_METADATA.each do |type, (tk_command, bind_option, natively_scrollable)|
      widget_type = Teek::UI::WidgetTypes.for_type(type)

      refute_nil widget_type, "expected :#{type} to be registered as a WidgetType"
      assert widget_type.leaf?, ":#{type} should be a leaf"
      assert_equal tk_command, widget_type.tk_command, ":#{type} tk_command"
      bind_option.nil? ? assert_nil(widget_type.bind_option, ":#{type} bind_option") : assert_equal(bind_option, widget_type.bind_option, ":#{type} bind_option")
      assert_equal natively_scrollable, widget_type.natively_scrollable?, ":#{type} natively_scrollable?"
    end
  end

  def test_widget_dsl_carries_no_leaf_types_constant
    refute Teek::UI::WidgetDSL.const_defined?(:LEAF_TYPES)
  end

  def test_widget_dsl_carries_no_bind_options_constant
    refute Teek::UI::WidgetDSL.const_defined?(:BIND_OPTIONS)
  end

  def test_widget_dsl_carries_no_scrollable_types_constant
    refute Teek::UI::WidgetDSL.const_defined?(:SCROLLABLE_TYPES)
  end

  def test_canvas_is_registered_as_natively_scrollable
    widget_type = Teek::UI::WidgetTypes.for_type(:canvas)

    refute_nil widget_type
    assert widget_type.natively_scrollable?
  end

  def test_scroll_default_defaults_to_auto_scroll
    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_scroll_default__, tk_command: 'ttk::label')

    original = Teek::UI.auto_scroll
    begin
      Teek::UI.auto_scroll = :sentinel_value
      assert_equal :sentinel_value, widget_type.global_scroll_default
    ensure
      Teek::UI.auto_scroll = original
    end
  end

  def test_canvas_points_its_scroll_default_at_auto_scroll_canvas_not_auto_scroll
    widget_type = Teek::UI::WidgetTypes.for_type(:canvas)

    original = Teek::UI.auto_scroll_canvas
    begin
      Teek::UI.auto_scroll_canvas = :sentinel_value
      assert_equal :sentinel_value, widget_type.global_scroll_default
    ensure
      Teek::UI.auto_scroll_canvas = original
    end
  end

  def test_list_and_table_and_tree_and_text_area_use_the_shared_auto_scroll_default
    %i[list table tree text_area].each do |type|
      widget_type = Teek::UI::WidgetTypes.for_type(type)

      original = Teek::UI.auto_scroll
      begin
        Teek::UI.auto_scroll = :sentinel_value
        assert_equal :sentinel_value, widget_type.global_scroll_default, ":#{type} scroll_default"
      ensure
        Teek::UI.auto_scroll = original
      end
    end
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

    assert_nil widget_type.post_create(:app, :node, :path, :parent_path)
  end

  def test_post_create_runs_the_given_hook
    calls = []
    widget_type = Teek::UI::WidgetType.new(
      type: :__test_widget_type_post_create__, tk_command: 'ttk::label',
      post_create: ->(app, node, path, parent_path) { calls << [app, node, path, parent_path] }
    )

    widget_type.post_create(:app, :node, :path, :parent_path)

    assert_equal [[:app, :node, :path, :parent_path]], calls
  end

  def test_flow_defaults_to_nil
    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_no_flow__, tk_command: 'ttk::frame')

    assert_nil widget_type.flow
  end

  def test_arranged_defaults_to_true
    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_arranged_default__, tk_command: 'ttk::frame')

    assert widget_type.arranged?
  end

  def test_arranged_false_is_registered_and_read_back
    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_unarranged__, tk_command: 'toplevel', arranged: false)

    refute widget_type.arranged?
  end

  def test_window_is_registered_as_unarranged
    widget_type = Teek::UI::WidgetTypes.for_type(:window)

    refute_nil widget_type
    refute widget_type.arranged?
  end

  def test_column_and_row_are_registered_with_flow_config
    column = Teek::UI::WidgetTypes.for_type(:column)
    row = Teek::UI::WidgetTypes.for_type(:row)

    refute_nil column.flow
    refute_nil row.flow
    assert_equal 'top', column.flow[:side]
    assert_equal 'left', row.flow[:side]
  end

  # type -> [tk_command, leaf?, arranged?] for every special/branching
  # container type (grid, scrollable, tabs/tab, split/pane, menu_bar/
  # context_menu).
  SPECIAL_TYPE_METADATA = {
    grid: ['ttk::frame', false, true],
    scrollable: ['ttk::frame', false, true],
    tabs: ['ttk::notebook', false, true],
    tab: ['ttk::frame', false, false],
    split: ['ttk::panedwindow', false, true],
    pane: ['ttk::frame', false, false],
    menu_bar: ['menu', false, false],
    context_menu: ['menu', false, false],
  }.freeze

  def test_every_special_type_is_registered_with_the_right_metadata
    SPECIAL_TYPE_METADATA.each do |type, (tk_command, leaf, arranged)|
      widget_type = Teek::UI::WidgetTypes.for_type(type)

      refute_nil widget_type, "expected :#{type} to be registered as a WidgetType"
      assert_equal tk_command, widget_type.tk_command, ":#{type} tk_command"
      assert_equal leaf, widget_type.leaf?, ":#{type} leaf?"
      assert_equal arranged, widget_type.arranged?, ":#{type} arranged?"
    end
  end

  def test_tab_pane_split_menu_bar_context_menu_have_no_auto_generated_dsl_method
    calls = []
    fake_module = Class.new {
      define_method(:append_container) { |*args, &block| calls << args }
      define_method(:append_leaf) { |*args| calls << args }
    }.new

    %i[tab pane split menu_bar context_menu].each do |type|
      Teek::UI::WidgetTypes.for_type(type).define_dsl_method!(fake_module.singleton_class)
    end

    refute fake_module.respond_to?(:tab)
    refute fake_module.respond_to?(:pane)
    refute fake_module.respond_to?(:split)
    refute fake_module.respond_to?(:menu_bar)
    refute fake_module.respond_to?(:context_menu)
    assert_empty calls
  end

  def test_grid_scrollable_tabs_composed_validators_are_registered_exactly_once
    assert_equal 1, Teek::UI::WidgetValidators.for_type(:grid).length
    assert_equal 1, Teek::UI::WidgetValidators.for_type(:tab).length
    assert_equal 1, Teek::UI::WidgetValidators.for_type(:pane).length
    assert_empty Teek::UI::WidgetValidators.for_type(:scrollable)
    assert_empty Teek::UI::WidgetValidators.for_type(:tabs)
  end

  def test_grid_has_a_custom_arrange_strategy
    assert Teek::UI::WidgetTypes.for_type(:grid).arrange?
  end

  def test_scrollable_has_custom_children_and_arrange_strategies
    widget_type = Teek::UI::WidgetTypes.for_type(:scrollable)

    assert widget_type.custom_children?
    assert widget_type.arrange?
  end

  def test_menu_bar_and_context_menu_have_a_custom_create_strategy
    assert Teek::UI::WidgetTypes.for_type(:menu_bar).custom_create?
    assert Teek::UI::WidgetTypes.for_type(:context_menu).custom_create?
  end

  def test_panel_has_none_of_the_special_strategies
    widget_type = Teek::UI::WidgetTypes.for_type(:panel)

    refute widget_type.arrange?
    refute widget_type.custom_children?
    refute widget_type.custom_create?
  end

  def test_arrange_defaults_to_absent
    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_no_arrange__, tk_command: 'ttk::frame')

    refute widget_type.arrange?
  end

  def test_arrange_runs_the_given_hook
    calls = []
    widget_type = Teek::UI::WidgetType.new(
      type: :__test_widget_type_arrange__, tk_command: 'ttk::frame',
      arrange: ->(realizer, node, children) { calls << [realizer, node, children] }
    )

    assert widget_type.arrange?
    widget_type.arrange(:realizer, :node, :children)

    assert_equal [[:realizer, :node, :children]], calls
  end

  def test_flow_computes_an_arrange_hook_that_delegates_to_arrange_flow
    fake_realizer = Class.new {
      attr_reader :calls
      def initialize
        @calls = []
      end
      def arrange_flow(node, children, flow)
        @calls << [node, children, flow]
      end
    }.new

    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_flow__, tk_command: 'ttk::frame', flow: { side: 'top' })

    assert widget_type.arrange?
    widget_type.arrange(fake_realizer, :node, :children)

    assert_equal [[:node, :children, { side: 'top' }]], fake_realizer.calls
  end

  def test_custom_children_defaults_to_absent
    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_no_custom_children__, tk_command: 'ttk::frame')

    refute widget_type.custom_children?
  end

  def test_custom_children_runs_the_given_hook
    calls = []
    widget_type = Teek::UI::WidgetType.new(
      type: :__test_widget_type_custom_children__, tk_command: 'ttk::frame',
      custom_children: ->(realizer, node, path) { calls << [realizer, node, path] }
    )

    assert widget_type.custom_children?
    widget_type.custom_children(:realizer, :node, :path)

    assert_equal [[:realizer, :node, :path]], calls
  end

  def test_custom_create_defaults_to_absent
    widget_type = Teek::UI::WidgetType.new(type: :__test_widget_type_no_custom_create__, tk_command: 'menu')

    refute widget_type.custom_create?
  end

  def test_custom_create_runs_the_given_hook
    calls = []
    widget_type = Teek::UI::WidgetType.new(
      type: :__test_widget_type_custom_create__, tk_command: 'menu',
      custom_create: ->(realizer, node, parent_path) { calls << [realizer, node, parent_path] }
    )

    assert widget_type.custom_create?
    widget_type.custom_create(:realizer, :node, :parent_path)

    assert_equal [[:realizer, :node, :parent_path]], calls
  end

  def test_widget_dsl_carries_no_container_types_constant
    refute Teek::UI::WidgetDSL.const_defined?(:CONTAINER_TYPES)
  end

  %i[TK_COMMANDS MENU_ROOT_TYPES NOT_ARRANGED_TYPES].each do |const_name|
    define_method("test_realizer_carries_no_#{const_name.downcase}_constant") do
      require 'teek/ui/realizer'
      refute Teek::UI::Realizer.const_defined?(const_name)
    end
  end
end
