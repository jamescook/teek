# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Real-Tk half of WidgetTypes' coverage - registry mechanics (register/
# for_type/each/on_register, leaf defaults, validator forwarding) are
# covered headlessly in test_widget_types.rb; these prove the actual dual
# path against a live app: `:divider` (the one migrated leaf) realizes
# byte-identically to before, and a brand-new custom type lights up across
# the DSL, the realizer, and the validator the moment it's registered, with
# no edits to any legacy list.
class TestWidgetTypesRealTk < Minitest::Test
  include TeekTestHelper

  def test_divider_realizes_as_a_real_ttk_separator
    assert_tk_app("the migrated :divider leaf should still realize as a real ttk::separator") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Widget Types Test') do |ui|
        ui.divider(:sep)
      end
      session.run_async
      session.app.update

      assert_equal 'TSeparator', session.app.tcl_eval("winfo class #{session[:sep].path}")
      assert session.app.winfo.ismapped?(session[:sep].path)

      session.app.destroy
    end
  end

  def test_a_custom_registered_widget_type_lights_up_dsl_realize_and_validate
    assert_tk_app("registering a new WidgetType should light up ui.<type>, its realize, and its validator - with no legacy-list edits") do
      require 'teek/ui'

      custom_type = :__test_widget_type_end_to_end__
      validated = []
      validator = ->(node, parent, _document, _errors) { validated << [node.type, parent&.type] }

      Teek::UI::WidgetTypes.register(
        Teek::UI::WidgetType.new(type: custom_type, tk_command: 'ttk::label', validator: validator)
      )

      session = Teek::UI.app(title: 'Widget Types Test') do |ui|
        ui.send(custom_type, :thing, text: 'Hi')
      end
      session.run_async
      session.app.update

      # realize: a real ttk::label got created, with the right opts
      assert_equal 'Hi', session.app.command(session[:thing].path, :cget, '-text')

      # validate: the composed validator ran during session.realize's
      # internal Validator.validate! call, seeing the right node/parent types
      assert_equal [[custom_type, :root]], validated

      session.app.destroy
    end
  end

  def test_a_custom_widget_type_without_a_validator_realizes_fine_and_is_never_dispatched
    assert_tk_app("a descriptor with no validator: should realize normally and never appear in WidgetValidators") do
      require 'teek/ui'

      custom_type = :__test_widget_type_no_validator__
      Teek::UI::WidgetTypes.register(
        Teek::UI::WidgetType.new(type: custom_type, tk_command: 'ttk::label')
      )

      session = Teek::UI.app(title: 'Widget Types Test') { |ui| ui.send(custom_type, :thing, text: 'Hi') }
      session.run_async
      session.app.update

      assert_equal 'Hi', session.app.command(session[:thing].path, :cget, '-text')
      assert_empty Teek::UI::WidgetValidators.for_type(custom_type)

      session.app.destroy
    end
  end
end
