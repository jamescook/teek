# frozen_string_literal: true

require_relative 'command_interceptors'
require_relative 'callback_registry'

module Teek
  # @api private
  #
  # Registered for the "canvas" {CommandInterceptors} entry below.
  #
  # Canvas items aren't windows (only the canvas itself is one), so a bound
  # item's callback never fires <Destroy> on its own, and `canvas delete`
  # is silent - the same leak shape menu entries have. Unlike menu or
  # text/treeview tags, canvas has no "list every live binding" enumeration
  # command (no analogue to menu's `index end` or text's `tag names`), so
  # this can't do a full-scan reconcile. Instead it re-queries only the
  # (tagOrId, sequence) keys it already knows about - via `canvas bind
  # tagOrId sequence`, the 2-arg read form - after every bind/delete call,
  # and lets whatever no longer resolves drop out.
  #
  # A binding on a numeric item id is released this way once that item is
  # deleted (Tk's Tk_DeleteAllBindings clears its binding-table entries
  # along with it). A binding on a tag is NOT released by deleting a
  # tagged item - the tag itself isn't an item, so its binding-table entry
  # persists independent of which (if any) items currently carry that tag.
  module CanvasBindInterceptor
    MUTATING_SUBCOMMANDS = %w[bind delete].freeze

    def self.call(app, path, args, kwargs)
      sub = args[0]&.to_s
      return nil unless MUTATING_SUBCOMMANDS.include?(sub)

      result = app.raw_command(path, *args, **kwargs)
      app.callback_registry.reconcile([:canvas_bind, path]) { |before| requery(app, path, before, sub, args) }
      result
    end

    def self.requery(app, path, before, sub, args)
      keys = before.keys
      keys += [[args[1].to_s, args[2].to_s]] if sub == 'bind' && args.length >= 4

      keys.uniq.each_with_object({}) do |(tag_or_id, seq), after|
        # Unlike a tag (a plain Tcl string, always a valid query target even
        # if nothing currently carries it), a numeric item id is a hash key
        # into the canvas's item table - querying one after its item is
        # deleted raises "item \"N\" doesn't exist" rather than returning
        # empty, so a deleted item's binding has to be dropped via rescue,
        # not by checking the result.
        current = begin
          app.tcl_eval("#{path} bind #{tag_or_id} #{seq}")
        rescue Teek::TclError
          ''
        end
        after[[tag_or_id, seq]] = Regexp.last_match(1) if current =~ /\Aruby_callback (\S+)\z/
      end
    end
  end

  CommandInterceptors.register('canvas', 'canvas_bind') { |*a| CanvasBindInterceptor.call(*a) }
end
