# frozen_string_literal: true

module Teek
  module UI
    # @api private
    #
    # A single widget/node type's own metadata, self-contained enough that
    # {WidgetDSL} (the builder), {Realizer}, and {Validator} can each treat
    # a registered type exactly like a hand-written entry in their own
    # legacy per-type lists (CONTAINER_TYPES, TK_COMMANDS, WidgetValidators's
    # own manual registrations) - see {WidgetTypes}.
    #
    # Leaf defaults cover the common case, so a real widget is a ~5-line
    # descriptor: +WidgetType.new(type: :divider, tk_command:
    # 'ttk::separator')+ is a complete, working leaf widget. A container,
    # or a widget needing bespoke DSL methods/realize setup, overrides
    # +dsl:+/+post_create:+.
    class WidgetType
      attr_reader :type, :tk_command, :bind_option, :validator, :flow

      # @param type [Symbol] the node type this describes, e.g. +:divider+
      # @param tk_command [String] the Tk widget-creation command, e.g. +'ttk::separator'+
      # @param leaf [Boolean] true for a childless widget (the default);
      #   false for a container that holds a DSL subtree
      # @param natively_scrollable [Boolean] whether this widget already
      #   speaks Tk's -yscrollcommand/-xscrollcommand protocol - see
      #   {Realizer#auto_scrollable?}, which consults this for a registered type
      # @param arranged [Boolean] whether a geometry manager (pack/grid)
      #   should place this node inside its parent - true (the default) for
      #   almost everything; false for a type placed some other way
      #   entirely, e.g. a toplevel window (placed by the window manager,
      #   not its nominal parent) or a tab/pane (placed by its own
      #   container's `add` command) - see {Realizer::NOT_ARRANGED_TYPES}
      #   (the still-hardcoded remainder) and {Realizer#unarranged?}, which
      #   consults this for a registered type
      # @param bind_option [Symbol, nil] the Tk option `bind:` plugs a
      #   {Var} into for this widget (+:textvariable+/+:variable+/...) -
      #   +nil+ (the default) means this widget doesn't support `bind:`
      # @param flow [Hash, nil] flow-packing config for a `column`/`row`-
      #   style container (side/main_pad/cross_pad/main_fill/cross_fill/
      #   anchor) - +nil+ (the default) means this type isn't flow-arranged
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
      # @param post_create [#call, nil] +->(app, node, path, parent_path) { ... }+,
      #   run right after the generic widget-creation command at realize -
      #   mirrors what {Realizer#setup_tab}/{Realizer#setup_pane} do for
      #   not-yet-migrated types (see e.g. {WindowRealize} for :window's
      #   own use of this hook). Defaults to a no-op.
      def initialize(type:, tk_command:, leaf: true, natively_scrollable: false, arranged: true,
                      bind_option: nil, flow: nil, validator: nil, dsl: nil, post_create: nil)
        @type = type.to_sym
        @tk_command = tk_command
        @leaf = leaf
        @natively_scrollable = natively_scrollable
        @arranged = arranged
        @bind_option = bind_option
        @flow = flow
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

      # @return [Boolean]
      def arranged?
        @arranged
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
      # @param parent_path [String]
      # @return [void]
      def post_create(app, node, path, parent_path)
        @post_create&.call(app, node, path, parent_path)
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
