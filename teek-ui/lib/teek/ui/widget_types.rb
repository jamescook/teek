# frozen_string_literal: true

require_relative 'widget_type'
require_relative 'widget_validators'

module Teek
  module UI
    # @api private
    #
    # Central registry of {WidgetType} descriptors, mirroring
    # {Teek::CommandInterceptors}'s own register/for_type shape - the seam
    # that lets {WidgetDSL}, {Realizer}, and {Validator} each treat a
    # registered type exactly like a hand-maintained entry in their own
    # legacy per-type list, without editing those lists.
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
    # {WidgetValidators} right here, at registration time - {Validator}
    # itself needs no separate dual-path branch for descriptor-composed
    # validators, since they end up dispatched through the exact same
    # +WidgetValidators.for_type+ call every other validator already goes
    # through.
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
