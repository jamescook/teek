# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

class TestGrid < Minitest::Test
  include TeekTestHelper

  def test_labeled_field_form_realizes_at_the_right_positions
    assert_tk_app("the canonical 2-column labeled-field form should realize with correct grid positions") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Grid Test') do |ui|
        ui.grid(:form, gap: 4) do |g|
          g.cell(row: 0, col: 0) { g.label(text: 'Name:') }
          g.cell(row: 0, col: 1) { g.text_box(:name_field) }
          g.cell(row: 1, col: 0) { g.label(text: 'Email:') }
          g.cell(row: 1, col: 1) { g.text_box(:email_field) }
          g.stretch(columns: [1])
        end
      end
      session.run_async
      session.app.update

      name_info = session.app.command(:grid, :info, session[:name_field].path)
      assert_match(/-row 0/, name_info)
      assert_match(/-column 1/, name_info)

      email_info = session.app.command(:grid, :info, session[:email_field].path)
      assert_match(/-row 1/, email_info)
      assert_match(/-column 1/, email_info)

      # the input column (1) is the one that should absorb extra width
      weight = session.app.tcl_eval("grid columnconfigure #{session[:form].path} 1 -weight")
      assert_equal '1', weight

      session.app.destroy
    end
  end

  def test_span_produces_a_real_columnspan
    assert_tk_app("span: should produce a real -columnspan in the realized grid") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Grid Test') do |ui|
        ui.grid(:form) do |g|
          g.cell(row: 0, col: 0) { g.label(text: 'Name:') }
          g.cell(row: 0, col: 1) { g.text_box(:name_field) }
          g.cell(row: 1, col: 0, span: 2) { g.divider(:sep) }
        end
      end
      session.run_async
      session.app.update

      sep_info = session.app.command(:grid, :info, session[:sep].path)
      assert_match(/-columnspan 2/, sep_info)

      session.app.destroy
    end
  end

  def test_a_widget_placed_directly_in_a_grid_without_cell_is_caught_by_validation
    assert_tk_app("a grid child never wrapped in g.cell should be caught by validation, before any Tk call happens") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Grid Test') do |ui|
        ui.grid(:form) { |g| g.label(:oops, text: 'no cell') }
      end

      error = assert_raises(Teek::UI::ValidationError) { session.realize }
      assert_match(/cell/i, error.message)
      assert_match(/oops/, error.message)

      # validation runs before any interpreter is constructed at all - a
      # failed realize never gets far enough to leave anything to clean up.
      assert_raises(Teek::UI::NotRealizedError) { session.app }
    end
  end

  def test_a_widget_added_to_a_grid_without_cell_via_session_add_still_raises_at_realize
    assert_tk_app("session.add skips validation, so the realizer's own backstop check is what catches this instead") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Grid Test') do |ui|
        ui.grid(:form) { |g| g.cell(row: 0, col: 0) { g.label(text: 'Name:') } }
      end
      session.run_async
      session.app.update

      error = assert_raises(ArgumentError) { session.add(:form) { |a| a.label(:oops, text: 'no cell') } }
      assert_match(/cell/i, error.message)
      assert_match(/oops/, error.message)

      session.app.destroy
    end
  end
end
