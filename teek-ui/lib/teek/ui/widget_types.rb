# frozen_string_literal: true

require_relative 'widget_type'
require_relative 'widget_validators'

module Teek
  module UI
    # @api private
    #
    # Central registry of {WidgetType} descriptors, mirroring
    # {Teek::CommandInterceptors}'s own register/for_type shape - one
    # registered descriptor per node type is the single source of truth
    # {WidgetDSL}, {Realizer}, and {Validator} each dispatch to for that
    # type's own build/realize/validate behavior.
    #
    # Unlike {Teek::CommandInterceptors} (consulted per-call with a type
    # already in hand) or {WidgetValidators} (many validators can share one
    # type), exactly one descriptor owns a given type here, and consumers
    # need the full set up front to drive codegen - so this adds two things
    # CommandInterceptors doesn't need: {.each} (enumerate every registered
    # type) and {.on_register} (subscribe to every past AND future
    # registration, so load order between this file and a consumer like
    # {WidgetDSL} never matters).
    #
    # A descriptor's +validator:+ (see {WidgetType}) is forwarded into
    # {WidgetValidators} right here, at registration time, so it's
    # dispatched through the exact same +WidgetValidators.for_type+ call
    # every other validator goes through - {Validator} itself carries no
    # awareness of descriptors at all.
    class WidgetTypes
      class << self
        # @param widget_type [WidgetType]
        # @return [WidgetType] +widget_type+, for chaining
        # @raise [ArgumentError] if +widget_type.type+ is already registered
        def register(widget_type)
          key = widget_type.type.to_s
          if types.key?(key)
            raise ArgumentError, "widget type :#{widget_type.type} is already registered"
          end

          types[key] = widget_type
          if widget_type.validator
            WidgetValidators.register(widget_type.type) { |*args| widget_type.validator.call(*args) }
          end
          callbacks.each { |callback| callback.call(widget_type) }

          widget_type
        end

        # @param type [Symbol, String]
        # @return [WidgetType, nil]
        def for_type(type)
          types[type.to_s]
        end

        # @yieldparam widget_type [WidgetType]
        # @return [Enumerator] if no block given
        def each(&block)
          return enum_for(:each) unless block

          types.each_value(&block)
        end

        # Subscribes +block+ to every type registered from now on, and
        # immediately replays every type already registered - so a
        # subscriber (namely {WidgetDSL}'s own codegen) sees every type
        # regardless of whether it loaded before or after this file
        # populated its own built-ins.
        # @yieldparam widget_type [WidgetType]
        # @return [void]
        def on_register(&block)
          types.each_value(&block)
          callbacks << block
        end

        private

        def types
          @types ||= {}
        end

        def callbacks
          @callbacks ||= []
        end
      end
    end
  end
end

require_relative 'widget_types/divider'
require_relative 'widget_types/text_box'
require_relative 'widget_types/text_area'
require_relative 'widget_types/label'
require_relative 'widget_types/button'
require_relative 'widget_types/checkbox'
require_relative 'widget_types/radio'
require_relative 'widget_types/slider'
require_relative 'widget_types/dropdown'
require_relative 'widget_types/number_box'
require_relative 'widget_types/list'
require_relative 'widget_types/table'
require_relative 'widget_types/tree'
require_relative 'widget_types/progress'
require_relative 'widget_types/panel'
require_relative 'widget_types/group'
require_relative 'widget_types/canvas'
require_relative 'widget_types/window'
require_relative 'widget_types/column'
require_relative 'widget_types/row'
require_relative 'widget_types/spacer'
require_relative 'widget_types/grid'
require_relative 'widget_types/scrollable'
require_relative 'widget_types/tabs'
require_relative 'widget_types/tab'
require_relative 'widget_types/split'
require_relative 'widget_types/pane'
require_relative 'widget_types/menu_bar'
require_relative 'widget_types/context_menu'
require_relative 'widget_types/menu_item'
require_relative 'widget_types/menu_checkbox'
require_relative 'widget_types/menu_radio'
