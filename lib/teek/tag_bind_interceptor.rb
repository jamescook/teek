# frozen_string_literal: true

require_relative 'command_interceptors'
require_relative 'callback_registry'

module Teek
  # @api private
  #
  # Live-scan helper for the shared "text"/"ttk::treeview" {CommandInterceptors}
  # entry below - both widgets have byte-identical `tag bind`/`tag names` shapes.
  #
  # Tags aren't windows, so a tag's bound callback never fires <Destroy> on
  # its own; the widget that owns it is typically long-lived and reused
  # (log panes, editors, tree views), so tags churn while the widget
  # persists. Unlike menu entries, a tag name is a stable hash key Tk never
  # renumbers, so reconciling is a straightforward full scan: enumerate
  # every live tag (`tag names`), read back what's bound to each
  # (`tag bind $tag` / `tag bind $tag $seq`), and release whatever dropped out.
  module TagBindInterceptor
    MUTATING_SUBCOMMANDS = %w[bind delete].freeze

    LIVE_COMMANDS_TCL_PROC = <<~TCL.freeze
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

    def self.live_command_ids(app, path)
      app.ensure_tcl_helper(:tag_live_commands) { LIVE_COMMANDS_TCL_PROC }
      raw = app.tcl_eval("::teek_tag_live_commands #{path}")
      app.split_list(raw).each_with_object({}) do |cmd, ids|
        ids[Regexp.last_match(1)] = Regexp.last_match(1) if cmd =~ /\Aruby_callback (\S+)\z/
      end
    end

    # A `tag bind`/`tag delete` call goes through raw_command unchanged (a
    # bound Proc is registered exactly like any other bind-shaped
    # positional arg), then reconciles tracked tag callbacks against Tk's
    # live tag-bind state.
    def self.call(app, path, args, kwargs)
      return nil unless args[0]&.to_s == 'tag' && MUTATING_SUBCOMMANDS.include?(args[1]&.to_s)

      result = app.raw_command(path, *args, **kwargs)
      app.callback_registry.reconcile([:tag_bind, path]) { |_before| live_command_ids(app, path) }
      result
    end
  end

  # text and ttk::treeview share byte-identical `tag bind`/`tag names`
  # shapes, so both register the same interceptor method.
  CommandInterceptors.register('text', 'tag_bind') { |*a| TagBindInterceptor.call(*a) }
  CommandInterceptors.register('ttk::treeview', 'tag_bind') { |*a| TagBindInterceptor.call(*a) }
end
