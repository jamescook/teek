# frozen_string_literal: true

require "teek"
require_relative "ui/version"
require_relative "ui/node"
require_relative "ui/document"
require_relative "ui/session"

module Teek
  # A DSL for building teek (Tk) apps - sugar over teek, not a wall around it.
  # Everything here compiles down to plain teek calls, and every handle keeps
  # an escape hatch back to the underlying {Teek::App}.
  module UI
    # Build an app. Constructs a {Session} (Tk-free - no {Teek::App} exists
    # yet), yields it to the block, and returns that same session so
    # `.run`/`.run_async` can be chained directly off the call. The
    # underlying app is created lazily, at realize (see {Session#realize}).
    #
    # @param title [String, nil] window title
    # @param app_opts [Hash] forwarded to {Teek::App.new} at realize (e.g. +debug:+, +track_widgets:+)
    # @yieldparam ui [Session]
    # @return [Session]
    #
    # @example
    #   Teek::UI.app(title: "Hello") do |ui|
    #     # widget/layout DSL calls go here
    #   end.run
    def self.app(title: nil, **app_opts, &block)
      session = Session.new(title: title, app_opts: app_opts)
      block.call(session) if block
      session
    end
  end
end
