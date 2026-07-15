# frozen_string_literal: true

require_relative 'handle'

module Teek
  module UI
    # A component's own public surface, returned by {WidgetDSL#component} -
    # the disciplined way a parent reaches a child's named widgets without
    # falling back to the flat, global `ui[]` index (which never sees into
    # a component's scope at all - see {WidgetDSL#[]}). Wraps a
    # (document, scope) pair and resolves names exactly the way `ui[]`
    # already does from inside the component's own block, just usable from
    # outside it - the parent addresses children through this facade, not
    # through `@document.find` or a captured {Node}.
    class ComponentHandle
      # @api private
      def initialize(document, scope)
        @document = document
        @scope = scope
      end

      # @param name [Symbol]
      # @return [Handle, nil] +nil+ if this component never declared
      #   +name+ - same nil-on-miss convention as {WidgetDSL#[]}
      def handle(name)
        node = @document.find(name, scope: @scope)
        node && Handle.new(node)
      end
      alias_method :[], :handle
    end
  end
end
