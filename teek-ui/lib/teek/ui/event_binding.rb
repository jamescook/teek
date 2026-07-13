# frozen_string_literal: true

module Teek
  module UI
    # An event a node wants wired up. +target+ is +nil+ to bind on the
    # node's own widget, or a Symbol naming another node's widget - resolved
    # by the realizer's link pass, after every node in the whole tree has
    # already been created, so a target declared later in the build still
    # resolves correctly (the forward-reference case). +subs+ are
    # {Teek::App#bind} substitution codes (e.g. +%i[x y]+) forwarded to the
    # handler when it fires.
    EventBinding = Data.define(:event, :handler, :target, :subs) do
      # @param event [String] a Tk bind event pattern, e.g. +"<Button-1>"+
      # @param handler [#call] called with whatever +subs+ substitutes
      # @param target [Symbol, nil] another node's name, or nil for self
      # @param subs [Array<Symbol, String>] see {Teek::App#bind}
      def initialize(event:, handler:, target: nil, subs: [])
        super
      end
    end
  end
end
