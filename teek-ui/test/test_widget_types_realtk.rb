# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

# Real-Tk half of WidgetTypes' coverage - registry mechanics (register/
# for_type/each/on_register, leaf defaults, validator forwarding) are
# covered headlessly in test_widget_types.rb; these exercise real
# realize/validate behavior against a live app: `:divider` realizes as a
# genuine `ttk::separator`, and a brand-new custom type lights up its own
# `ui.<type>` DSL method, realize, and validator the moment it's
# registered - proving the registry is what actually drives WidgetDSL/
# Realizer/Validator, not a parallel mechanism alongside them.
class TestWidgetTypesRealTk < Minitest::Test
  include TeekTestHelper

  tk_test "ui.divider should realize as a real ttk::separator" do
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

  tk_test "registering a new WidgetType should light up ui.<type>, its realize, and its validator" do
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

  tk_test "a descriptor with no validator: should realize normally and never appear in WidgetValidators" do
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
