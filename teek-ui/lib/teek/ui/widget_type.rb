# frozen_string_literal: true

module Teek
  module UI
    # @api private
    #
    # A single widget/node type's own metadata, self-contained enough that
    # {WidgetDSL} (the builder), {Realizer}, and {Validator} can each treat
    # a registered type exactly like a hand-written entry in their own
    # legacy per-type lists (LEAF_TYPES/CONTAINER_TYPES, TK_COMMANDS,
    # WidgetValidators's own manual registrations) - see {WidgetTypes}.
    #
    # Leaf defaults cover the common case, so a real widget is a ~5-line
    # descriptor: +WidgetType.new(type: :divider, tk_command:
    # 'ttk::separator')+ is a complete, working leaf widget. A container,
    # or a widget needing bespoke DSL methods/realize setup, overrides
    # +dsl:+/+post_create:+.
    class WidgetType
      attr_reader :type, :tk_command, :bind_option, :validator

      # @param type [Symbol] the node type this describes, e.g. +:divider+
      # @param tk_command [String] the Tk widget-creation command, e.g. +'ttk::separator'+
      # @param leaf [Boolean] true for a childless widget (the default);
      #   false for a container that holds a DSL subtree
      # @param natively_scrollable [Boolean] whether this widget already
      #   speaks Tk's -yscrollcommand/-xscrollcommand protocol - see
      #   {Realizer::NATIVELY_SCROLLABLE_TYPES}, which this mirrors for a
      #   registered type
      # @param bind_option [Symbol, nil] the Tk option `bind:` plugs a
      #   {Var} into for this widget (+:textvariable+/+:variable+/...) -
      #   +nil+ (the default) means this widget doesn't support `bind:`
      # @param validator [#call, nil] a +(node, parent, document, errors)+
      #   callable checking this type's own contract - a REFERENCE to an
      #   already-written validator (e.g. an existing WidgetValidators-style
      #   module), not duplicated logic. Composed into {WidgetValidators}
      #   automatically at {WidgetTypes.register} time, so {Validator}
      #   needs no separate awareness of descriptors at all.
      # @param dsl [Proc, nil] +->(mod) { ... }+, called once at
      #   {WidgetTypes.register} time (and replayed for any subscriber that
      #   joins later - see {WidgetTypes.on_register}) to define this
      #   type's `ui.<type>` method(s) on the builder module. Defaults to
      #   the leaf/container-appropriate +append_leaf+/+append_container+ call.
      # @param post_create [Proc, nil] +->(app, node, path) { ... }+, run
      #   right after the generic widget-creation command at realize -
      #   mirrors what +setup_window+/+setup_tab+/+setup_pane+ do for
      #   not-yet-migrated types. Defaults to a no-op.
      def initialize(type:, tk_command:, leaf: true, natively_scrollable: false,
                      bind_option: nil, validator: nil, dsl: nil, post_create: nil)
        @type = type.to_sym
        @tk_command = tk_command
        @leaf = leaf
        @natively_scrollable = natively_scrollable
        @bind_option = bind_option
        @validator = validator
        @dsl = dsl || default_dsl
        @post_create = post_create
      end

      # @return [Boolean]
      def leaf?
        @leaf
      end

      # @return [Boolean]
      def container?
        !@leaf
      end

      # @return [Boolean]
      def natively_scrollable?
        @natively_scrollable
      end

      # Defines this type's `ui.<type>` method(s) on +mod+ (the {WidgetDSL}
      # module) - see {WidgetTypes.on_register}, which drives this.
      # @param mod [Module]
      # @return [void]
      def define_dsl_method!(mod)
        @dsl.call(mod)
      end

      # Runs this type's post-creation realize setup, if any - a no-op
      # unless +post_create:+ was given.
      # @param app [Teek::App]
      # @param node [Node]
      # @param path [String]
      # @return [void]
      def post_create(app, node, path)
        @post_create&.call(app, node, path)
      end

      private

      def default_dsl
        widget_type = self
        if leaf?
          ->(mod) {
            mod.send(:define_method, widget_type.type) { |name = nil, **opts|
              append_leaf(widget_type.type, name, opts)
            }
          }
        else
          ->(mod) {
            mod.send(:define_method, widget_type.type) { |name = nil, **opts, &block|
              append_container(widget_type.type, name, opts, &block)
            }
          }
        end
      end
    end
  end
end
