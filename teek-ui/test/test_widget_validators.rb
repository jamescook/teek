# frozen_string_literal: true

require_relative 'test_helper'
require 'teek/ui/widget_validators'
require 'teek/ui/session'
require 'teek/ui/validator'

class TestWidgetValidators < Minitest::Test
  def build_session
    Teek::UI::Session.new(title: 'Widget Validators Test')
  end

  def test_for_type_returns_an_empty_array_for_an_unregistered_type
    assert_equal [], Teek::UI::WidgetValidators.for_type(:__never_registered__)
  end

  def test_register_and_for_type_round_trip
    calls = []
    Teek::UI::WidgetValidators.register(:__test_widget_validators_round_trip__) { |*args| calls << args }

    Teek::UI::WidgetValidators.for_type(:__test_widget_validators_round_trip__).each { |v| v.call(:node, :parent, :document, :errors) }

    assert_equal [[:node, :parent, :document, :errors]], calls
  end

  def test_for_type_accepts_a_string_type_too
    Teek::UI::WidgetValidators.register(:__test_widget_validators_string_type__) { }

    refute_empty Teek::UI::WidgetValidators.for_type('__test_widget_validators_string_type__')
  end

  def test_describe_formats_a_named_node
    document = Teek::UI::Document.new
    node = document.create(type: :button, name: :go)

    assert_equal '#button(:go)', Teek::UI::WidgetValidators.describe(node)
  end

  def test_describe_formats_an_unnamed_node
    document = Teek::UI::Document.new
    node = document.create(type: :button)

    assert_equal 'an unnamed #button', Teek::UI::WidgetValidators.describe(node)
  end

  def test_describe_of_nil_is_the_document_root
    assert_equal 'the document root', Teek::UI::WidgetValidators.describe(nil)
  end

  def test_a_custom_registered_validator_is_dispatched_during_validate_without_editing_validator
    document = Teek::UI::Document.new
    custom = document.create(type: :__test_widget_validators_custom_widget__, name: :thing)
    document.root.add_child(custom)

    seen = []
    Teek::UI::WidgetValidators.register(:__test_widget_validators_custom_widget__) { |node, parent, doc, errors|
      seen << [node, parent, doc, errors]
    }

    capture_io { Teek::UI::Validator.validate!(document) }

    assert_equal 1, seen.length
    node, parent, doc, errors = seen.first
    assert_same custom, node
    assert_same document.root, parent
    assert_same document, doc
    assert_kind_of Array, errors
  end

  def test_a_custom_registered_validator_can_append_an_error_that_surfaces_through_validate
    document = Teek::UI::Document.new
    custom = document.create(type: :__test_widget_validators_erroring_widget__, name: :thing)
    document.root.add_child(custom)

    Teek::UI::WidgetValidators.register(:__test_widget_validators_erroring_widget__) { |_n, _p, _d, errors|
      errors << 'a custom widget validator problem'
    }

    error = assert_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(document) }
    assert_match(/a custom widget validator problem/, error.message)
  end
end
