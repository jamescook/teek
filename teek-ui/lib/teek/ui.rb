# frozen_string_literal: true

require "teek"
require_relative "ui/version"
require_relative "ui/event_binding"
require_relative "ui/session"

module Teek
  # A DSL for building teek (Tk) apps - sugar over teek, not a wall around it.
  # Everything here compiles down to plain teek calls, and every handle keeps
  # an escape hatch back to the underlying {Teek::App}.
  module UI
    class << self
      # @return [Boolean] whether a bare list/text_area/table/tree
      #   auto-attaches a scrollbar with no `ui.scrollable` wrapper needed -
      #   true by default. Three levels can override it, most specific
      #   wins: a widget's own `scroll:` option, then `Teek::UI.app`'s own
      #   `scroll:`, then this global default.
      attr_accessor :auto_scroll

      # @return [Boolean] the same default, but for canvas specifically -
      #   false by default, since a canvas is as often fixed drawing as
      #   scrollable content, unlike the other native types.
      attr_accessor :auto_scroll_canvas
    end
    self.auto_scroll = true
    self.auto_scroll_canvas = false

    # Build an app. Constructs a {Session} (Tk-free - no {Teek::App} exists
    # yet), yields it to the block, and returns that same session so
    # `.run`/`.run_async` can be chained directly off the call. The
    # underlying app is created lazily, at realize (see {Session#realize}).
    #
    # @param title [String, nil] window title
    # @param scroll [Boolean, nil] app-wide override for whether native
    #   scrollable widgets auto-attach a scrollbar - between a widget's own
    #   `scroll:` (most specific) and {.auto_scroll}/{.auto_scroll_canvas}
    #   (global default). `nil` (the default) defers straight to the global.
    # @param app_opts [Hash] forwarded to {Teek::App.new} at realize (e.g. +debug:+, +track_widgets:+)
    # @yieldparam ui [Session]
    # @return [Session]
    #
    # @example
    #   Teek::UI.app(title: "Hello") do |ui|
    #     # widget/layout DSL calls go here
    #   end.run
    def self.app(title: nil, scroll: nil, **app_opts, &block)
      session = Session.new(title: title, scroll: scroll, app_opts: app_opts)
      block.call(session) if block
      session
    end
  end
end
