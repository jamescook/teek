# frozen_string_literal: true

require_relative 'command_interceptors'
require_relative 'callback_registry'

module Teek
  # @api private
  #
  # Live-scan helper for the "menu" {CommandInterceptors} entry below.
  #
  # Menu entries are not windows (only the menu itself is one), so they
  # never fire <Destroy>; entry deletion is silent and Tk renumbers the
  # survivors internally. Because of that, entry-level callbacks can't be
  # tracked by index or by any per-entry event - the only sound way to know
  # which callbacks are still needed is to ask Tk what's actually live
  # after every mutating call and release whatever dropped out.
  module MenuInterceptor
    ENTRY_SUBCOMMANDS = %w[add insert entryconfigure delete].freeze

    LIVE_COMMANDS_TCL_PROC = <<~TCL.freeze
      proc ::teek_menu_live_commands {path} {
        set result {}
        if {![winfo exists $path]} { return $result }
        set last [$path index end]
        if {$last eq "none"} { return $result }
        for {set i 0} {$i <= $last} {incr i} {
          set cmd ""
          catch {set cmd [$path entrycget $i -command]}
          lappend result $cmd
        }
        return $result
      }
    TCL

    def self.live_command_ids(app, path)
      app.ensure_tcl_helper(:menu_live_commands) { LIVE_COMMANDS_TCL_PROC }
      raw = app.tcl_eval("::teek_menu_live_commands #{path}")
      app.split_list(raw).each_with_object({}) do |cmd, ids|
        ids[Regexp.last_match(1)] = Regexp.last_match(1) if cmd =~ /\Aruby_callback (\S+)\z/
      end
    end
  end

  # Any add/insert/entryconfigure/delete on a menu goes through raw_command
  # unchanged (any command: Proc it carries is already registered correctly
  # by raw_command itself), then reconciles tracked entry callbacks against
  # Tk's live entrycget values - see {MenuInterceptor}.
  CommandInterceptors.register('menu', 'menu_entry') do |app, path, args, kwargs|
    next nil unless MenuInterceptor::ENTRY_SUBCOMMANDS.include?(args[0]&.to_s)

    result = app.raw_command(path, *args, **kwargs)
    app.callback_registry.reconcile([:menu, path]) { |_before| MenuInterceptor.live_command_ids(app, path) }
    result
  end
end
