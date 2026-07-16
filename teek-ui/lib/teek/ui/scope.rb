# frozen_string_literal: true

module Teek
  module UI
    # A component's build-time namespace - ambient builder state, kept on
    # a stack parallel to {WidgetDSL}'s own +@stack+ (see
    # {WidgetDSL#component}). A real object rather than a bare String/nil
    # on purpose: {TOP_LEVEL} is one unmistakable sentinel, checked by
    # identity (+#top_level?+/+#equal?+) rather than a value any caller
    # could accidentally collide with (+nil+, an empty string, a label
    # someone else also chose, ...). Two +Scope+ instances are never the
    # same scope just because they share a +label+ - {Document} keys on
    # identity, so every {WidgetDSL#component} call gets a genuinely
    # fresh, distinct scope regardless of what label (if any) it's given.
    class Scope
      # @return [Symbol, String, nil] a human-readable label, for error
      #   messages/debugging - never part of identity/equality
      attr_reader :label

      # @return [Scope, nil] the enclosing scope this one was opened
      #   inside - +nil+ only for {TOP_LEVEL} itself
      attr_reader :parent

      # @api private
      def initialize(label = nil, parent: nil)
        @label = label
        @parent = parent
      end

      # @return [Boolean] whether this is {TOP_LEVEL}
      def top_level?
        equal?(TOP_LEVEL)
      end
    end

    # The single sentinel for "not inside any component" - the default
    # scope for a build that never calls {WidgetDSL#component} at all.
    Scope::TOP_LEVEL = Scope.new(:top_level).freeze
  end
end
