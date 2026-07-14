# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/session'
require 'teek/ui/validator'

class TestValidator < Minitest::Test
  def build_session
    Teek::UI::Session.new(title: 'Validator Test')
  end

  def test_a_clean_tree_passes_without_raising_or_warning
    session = build_session
    session.column(:controls) { |c| c.button(:go, text: 'Go') }

    out, err = capture_io { Teek::UI::Validator.validate!(session.document) }

    assert_empty out
    assert_empty err
  end

  def test_stray_cell_intent_under_a_non_grid_parent_raises
    # only reachable via direct Node/Document manipulation - g.cell itself
    # already refuses to run outside a ui.grid block, so the public DSL
    # can never actually produce this.
    document = Teek::UI::Document.new
    panel = document.create(type: :panel, name: :not_a_grid)
    document.root.add_child(panel)
    stray = document.create(type: :label, name: :stray)
    stray.layout = { cell: { row: 0, col: 0, span: 1 } }
    panel.add_child(stray)

    error = assert_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(document) }
    assert_match(/stray/, error.message)
    assert_match(/not_a_grid/, error.message)
  end

  def test_a_tab_node_under_a_non_tabs_parent_raises
    # only reachable via direct Node/Document manipulation - WidgetDSL#tab
    # itself already refuses to run outside a ui.tabs block.
    document = Teek::UI::Document.new
    panel = document.create(type: :panel, name: :not_tabs)
    document.root.add_child(panel)
    stray = document.create(type: :tab, name: :stray, opts: { tab_label: 'Stray' })
    panel.add_child(stray)

    error = assert_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(document) }
    assert_match(/:tab/, error.message)
    assert_match(/not_tabs/, error.message)
  end

  def test_two_widgets_in_the_same_grid_cell_raises
    session = build_session
    session.grid(:g) do |g|
      g.cell(row: 0, col: 0) { g.label(:a, text: 'A') }
      g.cell(row: 0, col: 0) { g.label(:b, text: 'B') }
    end

    error = assert_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(session.document) }
    assert_match(/row 0, col 0/, error.message)
    assert_match(/:a\b/, error.message)
    assert_match(/:b\b/, error.message)
  end

  def test_different_grid_cells_do_not_raise
    session = build_session
    session.grid(:g) do |g|
      g.cell(row: 0, col: 0) { g.label(:a, text: 'A') }
      g.cell(row: 0, col: 1) { g.label(:b, text: 'B') }
    end

    capture_io { Teek::UI::Validator.validate!(session.document) }
  end

  def test_a_grid_child_missing_a_cell_raises
    # only reachable via direct Node/Document manipulation for a label
    # specifically (the DSL's own ui.grid { |g| g.label(...) } would need
    # g.cell to place it at all) - constructed directly here so the check
    # is exercised in isolation from #test_a_widget_placed_directly_in_a_grid_without_cell_is_caught_by_validation's
    # real-Tk, full-session version.
    document = Teek::UI::Document.new
    grid = document.create(type: :grid, name: :g)
    document.root.add_child(grid)
    oops = document.create(type: :label, name: :oops)
    grid.add_child(oops)

    error = assert_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(document) }
    assert_match(/cell/i, error.message)
    assert_match(/oops/, error.message)
  end

  def test_raw_op_and_other_not_grid_arranged_types_inside_a_grid_do_not_need_a_cell
    session = build_session
    session.grid(:g) { |g| g.raw { |_app| } }

    capture_io { Teek::UI::Validator.validate!(session.document) }
  end

  def test_both_grid_misuse_directions_can_be_reported_together
    document = Teek::UI::Document.new
    grid = document.create(type: :grid, name: :g)
    document.root.add_child(grid)
    missing_cell = document.create(type: :label, name: :missing_cell)
    grid.add_child(missing_cell)
    panel = document.create(type: :panel, name: :not_a_grid)
    document.root.add_child(panel)
    stray = document.create(type: :label, name: :stray)
    stray.layout = { cell: { row: 0, col: 0, span: 1 } }
    panel.add_child(stray)

    error = assert_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(document) }
    assert_match(/missing_cell/, error.message)
    assert_match(/stray/, error.message)
  end

  def test_dangling_event_target_raises_naming_both_ends
    # on_click et al never expose target: through the public Handle API
    # (it's an internal mechanism for future forward-reference features),
    # so this is only reachable via direct EventBinding construction too.
    session = build_session
    session.button(:trigger, text: 'Go')
    session.document.find(:trigger).events <<
      Teek::UI::EventBinding.new(event: '<Button-1>', handler: -> { }, target: :nope)

    error = assert_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(session.document) }
    assert_match(/trigger/, error.message)
    assert_match(/nope/, error.message)
  end

  def test_orphan_named_node_warns_by_default
    document = Teek::UI::Document.new
    document.create(type: :button, name: :lost) # never attached to any parent

    out, err = capture_io { Teek::UI::Validator.validate!(document) }

    assert_empty out
    assert_match(/lost/, err)
  end

  def test_orphan_named_node_raises_under_strict_mode
    document = Teek::UI::Document.new
    document.create(type: :button, name: :lost)

    error = assert_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(document, strict: true) }
    assert_match(/lost/, error.message)
  end

  def test_multiple_problems_all_appear_in_one_raised_error
    session = build_session
    session.grid(:g) do |g|
      g.cell(row: 0, col: 0) { g.label(:a, text: 'A') }
      g.cell(row: 0, col: 0) { g.label(:b, text: 'B') }
    end
    session.button(:trigger, text: 'Go')
    session.document.find(:trigger).events <<
      Teek::UI::EventBinding.new(event: '<Button-1>', handler: -> { }, target: :nope)

    error = assert_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(session.document) }
    assert_match(/row 0, col 0/, error.message)
    assert_match(/nope/, error.message)
  end
end
