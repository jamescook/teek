# frozen_string_literal: true

require "teek"
require_relative "ui/version"
require_relative "ui/session"

module Teek
  # A DSL for building teek (Tk) apps - sugar over teek, not a wall around it.
  # Everything here compiles down to plain teek calls, and every handle keeps
  # an escape hatch back to the underlying {Teek::App}.
  module UI
    # Build an app. Constructs the underlying {Teek::App}, yields the
    # {Session} to the block, and returns that same session so `.run`/
    # `.run_async` can be chained directly off the call.
    #
    # @param title [String, nil] window title
    # @param app_opts [Hash] forwarded to {Teek::App.new} (e.g. +debug:+, +track_widgets:+)
    # @yieldparam ui [Session]
    # @return [Session]
    #
    # @example
    #   Teek::UI.app(title: "Hello") do |ui|
    #     # widget/layout DSL calls go here
    #   end.run
    def self.app(title: nil, **app_opts, &block)
      raw_app = Teek::App.new(title: title, **app_opts)
      session = Session.new(raw_app)
      block.call(session) if block
      session
    end
  end
end
