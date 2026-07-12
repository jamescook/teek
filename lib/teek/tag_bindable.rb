# frozen_string_literal: true

module Teek
  # @api private
  #
  # Shared by any Widget behavior for a widget whose tags support their own
  # event bindings via a `tag bind` subcommand (text, ttk::treeview - both
  # confirmed to have byte-identical `tag bind`/`tag names` shapes). Not
  # itself a registered behavior - included by TextBehavior/TreeviewBehavior.
  #
  # Tags aren't windows, so a tag's bound callback never fires <Destroy> on
  # its own; the widget that owns it is typically long-lived and reused
  # (log panes, editors, tree views), so tags churn while the widget
  # persists. Unlike menu entries, a tag name is a stable hash key Tk never
  # renumbers, so reconciling is a straightforward full scan: enumerate
  # every live tag (`tag names`), read back what's bound to each
  # (`tag bind $tag` / `tag bind $tag $seq`), and let
  # {CallbackRegistry#reconcile} release whatever dropped out.
  module TagBindable
    TAG_LIVE_COMMANDS_TCL_PROC = <<~TCL.freeze
      proc ::teek_tag_live_commands {path} {
        set result {}
        foreach tag [$path tag names] {
          foreach seq [$path tag bind $tag] {
            lappend result [$path tag bind $tag $seq]
          }
        }
        return $result
      }
    TCL

    # Bind an event on a tag. Replaces any existing binding for the same
    # tag+event, releasing its callback.
    # @param tag [String] tag name
    # @param event [String] Tk event name, with or without angle brackets
    # @yield [*values] called when the event fires
    # @return [self]
    def tag_bind(tag, event, &block)
      event_str = event.start_with?('<') ? event : "<#{event}>"
      cb = app.register_callback(proc { |*args| block.call(*args) }, relay_break_continue: false)
      app.tcl_eval("#{path} tag bind #{tag} #{event_str} {ruby_callback #{cb}}")
      reconcile_tag_bindings
      self
    end

    # Remove an event binding previously set with {#tag_bind}.
    # @param tag [String] tag name
    # @param event [String] Tk event name, with or without angle brackets
    # @return [self]
    def tag_unbind(tag, event)
      event_str = event.start_with?('<') ? event : "<#{event}>"
      app.tcl_eval("#{path} tag bind #{tag} #{event_str} {}")
      reconcile_tag_bindings
      self
    end

    # Delete one or more tags, releasing any callbacks bound to them.
    # @param tags [Array<String>] tag names
    # @return [self]
    def tag_delete(*tags)
      app.command(path, 'tag', 'delete', *tags)
      reconcile_tag_bindings
      self
    end

    private

    def reconcile_tag_bindings
      app.callback_registry.reconcile([:tag_bind, path]) { |_before| live_tag_command_ids }
    end

    def live_tag_command_ids
      app.ensure_tcl_helper(:tag_live_commands) { TAG_LIVE_COMMANDS_TCL_PROC }
      raw = app.tcl_eval("::teek_tag_live_commands #{path}")
      app.split_list(raw).each_with_object({}) do |cmd, ids|
        if (m = cmd.match(/\Aruby_callback (\S+)\z/))
          ids[m[1]] = m[1]
        end
      end
    end
  end
end
