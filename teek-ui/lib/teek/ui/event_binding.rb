# frozen_string_literal: true

module Teek
  module UI
    # An event a node wants wired up at realize. +target+ is +nil+ to bind
    # on the node's own widget, or a Symbol naming another node's widget -
    # resolved by the realizer's link pass, after every node in the whole
    # tree has already been created, so a target declared later in the
    # build still resolves correctly (the forward-reference case).
    EventBinding = Data.define(:event, :handler, :target)
  end
end
