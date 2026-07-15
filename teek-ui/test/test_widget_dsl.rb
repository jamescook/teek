# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/session'

class TestWidgetDsl < Minitest::Test
  LEAF_WIDGET_TYPES = %i[
    text_box text_area label button checkbox radio slider dropdown
    number_box list table tree progress divider
  ].freeze

  def build_session
    Teek::UI::Session.new(title: 'Widget DSL Test')
  end

  def test_each_leaf_widget_method_appends_a_node_of_the_matching_type
    LEAF_WIDGET_TYPES.each do |method|
      session = build_session

      handle = session.send(method, :w, text: 'x')

      node = session.document.root.children.first
      assert_equal method, node.type, "##{method} should create a :#{method} node"
      assert_equal({ text: 'x' }, node.opts)
      assert_kind_of Teek::UI::Handle, handle
      assert_equal method, handle.type
    end
  end

  def test_leaf_widgets_work_unnamed
    session = build_session

    session.label(text: 'Hi')

    node = session.document.root.children.first
    assert_equal :label, node.type
    assert_nil node.name
    refute_nil node.key
  end

  def test_named_widget_is_addressable_via_bracket_lookup
    session = build_session

    session.text_box(:query)

    handle = session[:query]
    assert_kind_of Teek::UI::Handle, handle
    assert_equal :text_box, handle.type
    assert_equal :query, handle.name
  end

  def test_bracket_lookup_returns_nil_for_an_unknown_name
    session = build_session

    assert_nil session[:nope]
  end

  def test_duplicate_name_raises_through_the_dsl
    session = build_session
    session.button(:save)

    assert_raises(ArgumentError) { session.button(:save) }
  end

  def test_panel_nests_children_declared_in_its_block
    session = build_session

    session.panel(:controls) do |p|
      p.button(:go, text: 'Go')
      p.button(:stop, text: 'Stop')
    end

    panel_node = session.document.root.children.first
    assert_equal :panel, panel_node.type
    assert_equal [:button, :button], panel_node.children.map(&:type)
    assert_equal [:go, :stop], panel_node.children.map(&:name)
  end

  def test_container_block_yields_the_same_session_object
    session = build_session
    yielded = nil

    session.panel(:controls) { |p| yielded = p }

    # not a separate scoped builder - the same object, so a name declared
    # inside the block is addressable from outside it too via ui[:name]
    assert_same session, yielded
  end

  def test_nested_containers_attach_at_the_correct_depth
    session = build_session

    session.panel(:outer) do |outer|
      outer.panel(:inner) do |inner|
        inner.button(:deep)
      end
    end

    outer_node = session.document.root.children.first
    inner_node = outer_node.children.first
    deep_node = inner_node.children.first

    assert_equal :panel, outer_node.type
    assert_equal :panel, inner_node.type
    assert_equal :button, deep_node.type
    assert_equal [], deep_node.children
  end

  def test_a_container_without_a_block_still_creates_a_childless_node
    session = build_session

    session.window(:settings, title: 'Settings')

    node = session.document.root.children.first
    assert_equal :window, node.type
    assert_equal [], node.children
  end

  def test_box_is_a_synonym_for_panel
    session = build_session

    session.box(:sidebar)

    node = session.document.root.children.first
    assert_equal :panel, node.type
  end

  %i[group canvas window].each do |container|
    define_method("test_#{container}_is_a_container_that_nests_children") do
      session = build_session

      session.send(container, :c) { |b| b.label(:inner_label) }

      node = session.document.root.children.first
      assert_equal container, node.type
      assert_equal [:label], node.children.map(&:type)
    end
  end

  def test_var_is_tracked_on_the_session
    session = build_session

    speed = session.var(5)

    assert_kind_of Teek::UI::Var, speed
    assert_includes session.vars, speed
  end

  def test_var_names_are_unique_within_a_session
    session = build_session

    a = session.var(1)
    b = session.var(2)

    refute_equal a.name, b.name
  end

  def test_bind_translates_to_the_variable_option_for_a_slider
    session = build_session
    speed = session.var(5)

    session.slider(:s, from: 1, to: 10, bind: speed)

    node = session.document.root.children.first
    assert_equal speed.name, node.opts[:variable]
    refute node.opts.key?(:bind), "bind: should not leak through to the realized widget options"
  end

  def test_bind_translates_to_the_textvariable_option_for_a_text_box
    session = build_session
    speed = session.var(5)

    session.text_box(:t, bind: speed)

    node = session.document.root.children.first
    assert_equal speed.name, node.opts[:textvariable]
  end

  def test_bind_on_an_unsupported_widget_type_raises
    session = build_session
    speed = session.var(5)

    assert_raises(ArgumentError) { session.divider(:d, bind: speed) }
  end

  def test_scroll_on_an_unsupported_widget_type_raises
    session = build_session

    error = assert_raises(ArgumentError) { session.button(:go, scroll: true) }
    assert_match(/scroll:/, error.message)
  end

  def test_scroll_on_a_natively_scrollable_widget_type_does_not_raise
    session = build_session

    session.list(:items, scroll: false)
    session.canvas(:board, scroll: true)

    assert_equal [false, true], session.document.root.children.map { |n| n.opts[:scroll] }
  end

  def test_column_and_row_are_containers_carrying_gap_align_pad_in_opts
    session = build_session

    session.column(:c, gap: 8, align: :stretch, pad: 4) { |c| c.button(:go) }

    node = session.document.root.children.first
    assert_equal :column, node.type
    assert_equal({ gap: 8, align: :stretch, pad: 4 }, node.opts)
    assert_equal [:button], node.children.map(&:type)
  end

  def test_row_defaults_gap_align_pad_when_not_given
    session = build_session

    session.row(:r)

    node = session.document.root.children.first
    assert_equal :row, node.type
    assert_equal({}, node.opts)
  end

  def test_grow_is_captured_on_the_childs_layout_and_stripped_from_opts
    session = build_session

    session.column(:c) { |c| c.button(:go, text: 'Go', grow: true) }

    button_node = session.document.root.children.first.children.first
    assert_equal({ grow: true }, button_node.layout)
    assert_equal({ text: 'Go' }, button_node.opts)
  end

  def test_grow_defaults_to_nil_layout_when_not_given
    session = build_session

    session.button(:go)

    node = session.document.root.children.first
    assert_nil node.layout
  end

  def test_grow_works_on_a_container_child_too
    session = build_session

    session.column(:outer) { |o| o.row(:inner, grow: true) }

    inner_node = session.document.root.children.first.children.first
    assert_equal({ grow: true }, inner_node.layout)
  end

  def test_lazy_true_marks_the_container_node_lazy_and_is_stripped_from_opts
    session = build_session

    session.panel(:picker, lazy: true, text: 'ignored opt just for this test')

    node = session.document.root.children.first
    assert node.lazy?
    refute node.opts.key?(:lazy)
  end

  def test_lazy_defaults_to_false_when_not_given
    session = build_session

    session.panel(:picker)

    node = session.document.root.children.first
    refute node.lazy?
  end

  def test_spacer_is_a_leaf_node_with_grow_baked_in
    session = build_session

    session.column(:c) { |c| c.spacer }

    spacer_node = session.document.root.children.first.children.first
    assert_equal :spacer, spacer_node.type
    assert_equal({ grow: true }, spacer_node.layout)
    assert_equal [], spacer_node.children
  end

  def test_grid_is_a_container_type
    session = build_session

    session.grid(:g, gap: 6) { |g| g.cell(row: 0, col: 0) { g.label(text: 'User') } }

    node = session.document.root.children.first
    assert_equal :grid, node.type
    assert_equal({ gap: 6 }, node.opts)
  end

  def test_cell_tags_the_single_widget_it_creates_with_row_col_span
    session = build_session

    session.grid(:g) { |g| g.cell(row: 1, col: 2, span: 3) { g.label(:l, text: 'x') } }

    label_node = session.document.root.children.first.children.first
    assert_equal({ row: 1, col: 2, span: 3 }, label_node.layout[:cell])
  end

  def test_cell_span_defaults_to_1
    session = build_session

    session.grid(:g) { |g| g.cell(row: 0, col: 0) { g.label(:l, text: 'x') } }

    label_node = session.document.root.children.first.children.first
    assert_equal 1, label_node.layout[:cell][:span]
  end

  def test_cell_merges_with_an_existing_grow_layout_intent
    session = build_session

    session.grid(:g) { |g| g.cell(row: 0, col: 0) { g.text_box(:t, grow: true) } }

    node = session.document.root.children.first.children.first
    assert_equal true, node.layout[:grow]
    assert_equal({ row: 0, col: 0, span: 1 }, node.layout[:cell])
  end

  def test_cell_raises_if_its_block_creates_no_widget
    session = build_session

    error = assert_raises(ArgumentError) { session.grid(:g) { |g| g.cell(row: 0, col: 0) { } } }
    assert_match(/exactly one widget/, error.message)
  end

  def test_cell_raises_if_its_block_creates_more_than_one_widget
    session = build_session

    error = assert_raises(ArgumentError) do
      session.grid(:g) { |g| g.cell(row: 0, col: 0) { g.label(:a); g.label(:b) } }
    end
    assert_match(/exactly one widget/, error.message)
  end

  def test_cell_outside_a_grid_raises
    session = build_session

    error = assert_raises(ArgumentError) { session.cell(row: 0, col: 0) { } }
    assert_match(/grid/, error.message)
  end

  def test_stretch_sets_stretch_columns_and_rows_on_the_grid_nodes_opts
    session = build_session

    session.grid(:g) { |g| g.stretch(columns: [1], rows: [0]) }

    node = session.document.root.children.first
    assert_equal [1], node.opts[:stretch_columns]
    assert_equal [0], node.opts[:stretch_rows]
  end

  def test_stretch_outside_a_grid_raises
    session = build_session

    error = assert_raises(ArgumentError) { session.stretch(columns: [0]) }
    assert_match(/grid/, error.message)
  end

  def test_tabs_is_a_container_type
    session = build_session

    session.tabs(:t) { |t| t.tab('General') { |g| g.button(:go, text: 'Go') } }

    node = session.document.root.children.first
    assert_equal :tabs, node.type
    assert_equal [:tab], node.children.map(&:type)
  end

  def test_tab_stashes_its_label_and_nests_its_blocks_children
    session = build_session

    session.tabs { |t| t.tab('General') { |g| g.button(:go, text: 'Go') } }

    tab_node = session.document.root.children.first.children.first
    assert_equal 'General', tab_node.opts[:tab_label]
    assert_equal [:button], tab_node.children.map(&:type)
    assert_equal [:go], tab_node.children.map(&:name)
  end

  def test_tab_accepts_an_optional_name_for_ui_bracket_lookup
    session = build_session

    session.tabs { |t| t.tab('Advanced', :advanced_tab) }

    assert_equal :advanced_tab, session[:advanced_tab].name
    assert_equal :tab, session[:advanced_tab].type
  end

  def test_tab_outside_ui_tabs_raises
    session = build_session

    error = assert_raises(ArgumentError) { session.tab('General') }
    assert_match(/ui\.tabs/, error.message)
  end

  def test_split_is_a_container_type
    session = build_session

    session.split { |s| s.pane { |p| p.button(:go, text: 'Go') } }

    node = session.document.root.children.first
    assert_equal :split, node.type
    assert_equal [:pane], node.children.map(&:type)
  end

  def test_split_defaults_to_horizontal_orientation
    session = build_session

    session.split { }

    node = session.document.root.children.first
    assert_equal 'horizontal', node.opts[:orient]
  end

  def test_split_accepts_vertical_orientation
    session = build_session

    session.split(orientation: :vertical) { }

    node = session.document.root.children.first
    assert_equal 'vertical', node.opts[:orient]
  end

  def test_split_raises_on_an_invalid_orientation
    session = build_session

    error = assert_raises(ArgumentError) { session.split(orientation: :diagonal) }
    assert_match(/:horizontal or :vertical/, error.message)
  end

  def test_split_accepts_a_name_like_any_other_container
    session = build_session

    session.split(:main) { |s| s.pane { } }

    node = session.document.root.children.first
    assert_equal :main, node.name
  end

  def test_pane_nests_its_blocks_children
    session = build_session

    session.split { |s| s.pane { |p| p.button(:go, text: 'Go') } }

    pane_node = session.document.root.children.first.children.first
    assert_equal [:button], pane_node.children.map(&:type)
    assert_equal [:go], pane_node.children.map(&:name)
  end

  def test_pane_accepts_an_optional_name_for_ui_bracket_lookup
    session = build_session

    session.split { |s| s.pane(:left) }

    assert_equal :left, session[:left].name
    assert_equal :pane, session[:left].type
  end

  def test_pane_weight_is_stashed_in_opts_without_leaking_weight_itself
    session = build_session

    session.split { |s| s.pane(weight: 2) }

    pane_node = session.document.root.children.first.children.first
    assert_equal 2, pane_node.opts[:pane_weight]
    refute pane_node.opts.key?(:weight)
  end

  def test_pane_without_a_weight_stashes_nothing
    session = build_session

    session.split { |s| s.pane }

    pane_node = session.document.root.children.first.children.first
    refute pane_node.opts.key?(:pane_weight)
  end

  def test_pane_outside_ui_split_raises
    session = build_session

    error = assert_raises(ArgumentError) { session.pane }
    assert_match(/ui\.split/, error.message)
  end

  def test_raw_creates_a_raw_op_node_attached_to_the_current_parent
    session = build_session

    session.column(:c) { |c| c.raw { |_app| } }

    node = session.document.root.children.first.children.first
    assert_equal :raw_op, node.type
    assert_kind_of Proc, node.opts[:block]
  end

  def test_raw_does_not_execute_the_block_during_build
    session = build_session
    executed = false

    session.raw { |_app| executed = true }

    refute executed, "ui.raw should defer its block to realize, not run it during build"
  end

  def test_scrollable_nests_children_declared_in_its_block
    session = build_session

    session.scrollable(:region) do |s|
      s.list(:items)
    end

    node = session.document.root.children.first
    assert_equal :scrollable, node.type
    assert_equal [:list], node.children.map(&:type)
    assert_equal [:items], node.children.map(&:name)
  end

  def test_scrollable_x_and_y_opts_land_on_the_node
    session = build_session

    session.scrollable(:region, x: true, y: false) { |s| s.list(:items) }

    node = session.document.root.children.first
    assert_equal true, node.opts[:x]
    assert_equal false, node.opts[:y]
  end

  def test_scrollable_without_a_block_still_creates_a_childless_node
    session = build_session

    session.scrollable(:region)

    node = session.document.root.children.first
    assert_equal :scrollable, node.type
    assert_equal [], node.children
  end

  def test_screens_is_memoized_across_calls
    session = build_session

    assert_same session.screens, session.screens
  end

  def test_modal_defaults_to_nil
    session = build_session

    assert_nil session.modal
  end

  def test_modal_is_assignable_and_reads_back
    session = build_session
    stack = Teek::UI::ModalStack.new(on_enter: ->(_) { }, on_exit: -> { })

    session.modal = stack

    assert_same stack, session.modal
  end
end
