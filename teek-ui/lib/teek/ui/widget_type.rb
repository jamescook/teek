# frozen_string_literal: true

module Teek
  module UI
    # @api private
    #
    # A single widget/node type's own metadata: what it draws, how it's
    # built and arranged, what it validates - self-contained enough that
    # {WidgetDSL} (the builder), {Realizer}, and {Validator} can each treat
    # a registered type as the sole source of truth for it, dispatched by
    # node type via {WidgetTypes}.
    #
    # Leaf defaults cover the common case, so a real widget is a ~5-line
    # descriptor: +WidgetType.new(type: :divider, tk_command:
    # 'ttk::separator')+ is a complete, working leaf widget. A container,
    # or a widget needing bespoke DSL methods/realize setup, overrides
    # +dsl:+/+post_create:+.
    class WidgetType
      attr_reader :type, :tk_command, :bind_option, :validator, :flow

      # @param type [Symbol] the node type this describes, e.g. +:divider+
      # @param tk_command [String] the Tk widget-creation command, e.g.
      #   +'ttk::separator'+ - documentary only for a type that also sets
      #   +custom_create:+, since that hook bypasses the generic
      #   widget-creation call this would otherwise drive
      # @param leaf [Boolean] true for a childless widget (the default);
      #   false for a container that holds a DSL subtree
      # @param natively_scrollable [Boolean] whether this widget already
      #   speaks Tk's -yscrollcommand/-xscrollcommand protocol - see
      #   {Realizer#auto_scrollable?}, which consults this for a registered type
      # @param scroll_default [Symbol] which {Teek::UI} global default
      #   reader this type's own auto-scrollable wrapping falls back to
      #   when neither the widget's own +scroll:+ nor the session's
      #   app-wide override says otherwise - +:auto_scroll+ (the default)
      #   for most natively-scrollable types, +:auto_scroll_canvas+ for
      #   canvas specifically. Only meaningful alongside
      #   +natively_scrollable: true+ - see {Realizer#resolve_scroll}.
      # @param arranged [Boolean] whether a geometry manager (pack/grid)
      #   should place this node inside its parent - true (the default) for
      #   almost everything; false for a type placed some other way
      #   entirely, e.g. a toplevel window (placed by the window manager,
      #   not its nominal parent) or a tab/pane (placed by its own
      #   container's `add` command) - see {Realizer#unarranged?}, which
      #   consults this for a registered type
      # @param bind_option [Symbol, nil] the Tk option `bind:` plugs a
      #   {Var} into for this widget (+:textvariable+/+:variable+/...) -
      #   +nil+ (the default) means this widget doesn't support `bind:`
      # @param flow [Hash, nil] flow-packing config for a `column`/`row`-
      #   style container (side/main_pad/cross_pad/main_fill/cross_fill/
      #   anchor) - +nil+ (the default) means this type isn't flow-arranged.
      #   A convenience over +arrange:+ for exactly this shape: giving
      #   +flow:+ computes an +arrange:+ that delegates to
      #   {Realizer#arrange_flow} with this data, so most flow containers
      #   never need to touch +arrange:+ directly.
      # @param arrange [#call, nil] +->(realizer, node, children) { ... }+,
      #   replaces the realizer's generic "pack every child plainly"
      #   default arrangement for this type entirely - e.g. real Tk grid
      #   placement (row/col/span/stretch) for a `:grid`-shaped type. Since
      #   the logic usually needs realizer-private helpers (gap/align
      #   computation, error formatting, ...), the callable is typically a
      #   thin adapter delegating back via +realizer.send(:some_private_method, ...)+
      #   rather than reimplementing arrangement from scratch - see
      #   {Realizer#arrange_grid} for an example. +nil+ (the default,
      #   unless +flow:+ computed one) means the generic pack default applies.
      # @param custom_children [#call, nil] +->(realizer, node, path) { ... }+,
      #   replaces the realizer's generic "create every child normally"
      #   step for this type, once its OWN widget has already been created
      #   the normal way - e.g. `:scrollable`'s children live inside an
      #   embedded canvas+viewport it builds itself, not directly under its
      #   own path. +nil+ (the default) means children realize normally.
      # @param custom_create [#call, nil] +->(realizer, node, parent_path) { ... }+,
      #   replaces the realizer's ENTIRE per-node create/link handling for
      #   this type - no generic widget-creation call, no {#post_create},
      #   no {#arrange}/`custom_children`, no normal `link` processing
      #   (events/close-handler/child recursion) either. For a type whose
      #   realize model doesn't share ANY of that machinery at all - e.g.
      #   `:menu_bar`/`:context_menu`, realized via
      #   {Realizer#create_menu_tree}'s own bespoke traversal, using
      #   `Teek::App#menu` rather than a generic widget-creation command.
      #   +nil+ (the default) means this type goes through the normal
      #   create/link two-pass path.
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
      #   the leaf/container-appropriate +append_leaf+/+append_container+
      #   call - pass +->(mod) { }+ (a genuine no-op) for a type reachable
      #   only via a bespoke, hand-written top-level method with a
      #   different signature (e.g. `#tab`/`#pane`/`#split`, or
      #   `#menu_bar`/`#context_menu`), so the registry doesn't shadow it
      #   with a same-named generic method.
      # @param post_create [#call, nil] +->(app, node, path, parent_path) { ... }+,
      #   run right after the generic widget-creation command at realize -
      #   see {WindowRealize}/{TabRealize}/{PaneRealize} for real examples.
      #   Defaults to a no-op. Not called at all for a type that sets
      #   +custom_create:+, since that hook bypasses this entire step.
      def initialize(type:, tk_command:, leaf: true, natively_scrollable: false, arranged: true,
                      scroll_default: :auto_scroll, bind_option: nil, flow: nil, arrange: nil,
                      custom_children: nil, custom_create: nil, validator: nil, dsl: nil, post_create: nil)
        @type = type.to_sym
        @tk_command = tk_command
        @leaf = leaf
        @natively_scrollable = natively_scrollable
        @arranged = arranged
        @scroll_default = scroll_default
        @bind_option = bind_option
        @flow = flow
        @arrange = arrange || (flow && ->(realizer, node, children) { realizer.send(:arrange_flow, node, children, flow) })
        @custom_children = custom_children
        @custom_create = custom_create
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

      # @return [Boolean] the current value of this type's own
      #   {Teek::UI} global scroll-default reader (+scroll_default:+)
      def global_scroll_default
        Teek::UI.public_send(@scroll_default)
      end

      # @return [Boolean]
      def arranged?
        @arranged
      end

      # @return [Boolean] whether this type replaces the generic arrangement
      def arrange?
        !@arrange.nil?
      end

      # Runs this type's custom arrangement strategy.
      # @param realizer [Realizer]
      # @param node [Node]
      # @param children [Array<Node>] this node's arrangeable children
      # @return [void]
      def arrange(realizer, node, children)
        @arrange.call(realizer, node, children)
      end

      # @return [Boolean] whether this type replaces generic child creation
      def custom_children?
        !@custom_children.nil?
      end

      # Runs this type's custom child-creation strategy, once its own
      # widget already exists at +path+.
      # @param realizer [Realizer]
      # @param node [Node]
      # @param path [String]
      # @return [void]
      def custom_children(realizer, node, path)
        @custom_children.call(realizer, node, path)
      end

      # @return [Boolean] whether this type replaces the entire create/link handling
      def custom_create?
        !@custom_create.nil?
      end

      # Runs this type's entire create/link replacement.
      # @param realizer [Realizer]
      # @param node [Node]
      # @param parent_path [String]
      # @return [void]
      def custom_create(realizer, node, parent_path)
        @custom_create.call(realizer, node, parent_path)
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
