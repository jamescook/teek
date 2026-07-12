# frozen_string_literal: true

require_relative 'widget'
require_relative 'callback_registry'
require_relative 'tag_bindable'

module Teek
  # @api private
  #
  # Extended onto a {Widget} for Tk `ttk::treeview` widgets by
  # {App#create_widget} (registered below) - not meant to be used directly
  # or referenced by class.
  #
  # Two independent callback-leak surfaces:
  #
  # - Tag bindings (`tag bind`/`tag names`) are byte-identical in Tcl shape
  #   to Text's, so this just reuses {TagBindable} rather than duplicating
  #   it - #tag_bind/#tag_unbind/#tag_delete come from there.
  # - Column heading commands (`heading column -command`) are a plain
  #   widget-style option, not a menu/tag-shaped thing - reconfiguring one
  #   silently replaces the old value with no release hook, the same shape
  #   already fixed generically for widget options. It can't reuse that
  #   generic mechanism as-is, though: that tracks by option NAME alone
  #   within one container per widget, and two different columns both
  #   using `command:` would collide under the same key and wrongly
  #   release each other's callback. #heading tracks by (column, option)
  #   instead, via its own dedicated container.
  module TreeviewBehavior
    include TagBindable

    # Configure a column's heading. Any Proc passed as +command:+ is
    # tracked per column, released if that column's heading command is
    # replaced or the treeview is destroyed.
    # @param column [String, Symbol] column identifier (e.g. "#0", or a
    #   name from the -columns list)
    # @param kwargs heading options (e.g. text:, command:, ...)
    # @return [self]
    def heading(column, **kwargs)
      if kwargs[:command].is_a?(Proc)
        cb = app.register_callback(kwargs[:command], relay_break_continue: false)
        app.command(path, 'heading', column, **kwargs.merge(command: "ruby_callback #{cb}"))
        app.callback_registry.reconcile([:treeview_heading, path]) { |before| before.merge(column.to_s => cb) }
      else
        app.command(path, 'heading', column, **kwargs)
      end
      self
    end
  end

  Widget.register_behavior('ttk::treeview', TreeviewBehavior)
end
