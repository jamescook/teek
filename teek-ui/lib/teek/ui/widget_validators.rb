# frozen_string_literal: true

module Teek
  module UI
    # @api private
    #
    # Registry of per-node-type validators, mirroring {Teek::CommandInterceptors}'
    # own register(type, ...)/for_type(type) shape. {Validator} (the
    # coordinator) walks the whole {Document} exactly once; at each node it
    # looks up +WidgetValidators.for_type(node.type)+ and calls every
    # validator registered there.
    #
    # A registered validator receives +(node, parent, document, errors)+ and
    # must APPEND problem strings to +errors+ - it must never raise itself.
    # Unlike a {Teek::CommandInterceptors} entry (which "claims" a call and
    # returns its result), a widget validator has nothing to return and
    # nothing to claim exclusively - multiple validators for the same type
    # can coexist freely, and there's no ambiguity to detect.
    #
    # Registering a validator for a type is purely additive: a custom or
    # third-party widget can call {.register} to get its own contract
    # checked without editing this file or {Validator}, the same way a
    # custom widget can register a {Teek::CommandInterceptors} entry without
    # editing +teek.rb+.
    class WidgetValidators
      class << self
        # @param type [Symbol, String] the node type this validator applies to
        # @yieldparam node [Node]
        # @yieldparam parent [Node, nil]
        # @yieldparam document [Document]
        # @yieldparam errors [Array<String>]
        # @return [void]
        def register(type, &block)
          validators[type.to_s] << block
        end

        # @param type [Symbol, String]
        # @return [Array<Proc>] every validator registered for +type+, in
        #   registration order - empty if none are
        def for_type(type)
          validators[type.to_s]
        end

        # Shared node-describing helper every validator's error messages use
        # ("#label(:name)" or "an unnamed #label") - kept here rather than
        # duplicated per validator file, since every one of them needs it.
        # @param node [Node, nil]
        # @return [String]
        def describe(node)
          return 'the document root' unless node
          node.name ? "##{node.type}(:#{node.name})" : "an unnamed ##{node.type}"
        end

        private

        def validators
          @validators ||= Hash.new { |h, k| h[k] = [] }
        end
      end
    end
  end
end
