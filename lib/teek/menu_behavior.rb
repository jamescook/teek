# frozen_string_literal: true

require_relative 'widget'
require_relative 'callback_registry'

module Teek
  # @api private
  #
  # Extended onto a {Widget} for Tk `menu` widgets by {App#create_widget}
  # (registered below) - not meant to be used directly or referenced by
  # class. Provides menu entry management (add_command/add_cascade/etc.,
  # insert, entryconfigure, delete, clear, popup) without leaking the
  # Ruby callback registered for each entry's `-command`.
  #
  # Menu entries are not windows (only the menu itself is one), so they
  # never fire <Destroy>; entry deletion is silent and Tk renumbers the
  # survivors internally. Because of that, entry-level callbacks can't be
  # tracked by index or by any per-entry event - the only sound way to
  # know which callbacks are still needed is to ask Tk what's actually
  # live after every mutating call and release whatever dropped out, via
  # {CallbackRegistry#reconcile}.
  #
  # @example Rebuilding a context menu on every open
  #   menu = app.menu(".card.ctx")
  #   menu.clear
  #   menu.add_command(label: "Play", command: proc { play(rom) })
  #   menu.add_command(label: "Remove", command: proc { remove(rom) })
  #   menu.popup(x, y)
  #
  # @see App#menu
  module MenuBehavior
    ENTRY_TYPES = %i[command cascade checkbutton radiobutton separator].freeze

    ENTRY_TYPES.each do |type|
      define_method("add_#{type}") do |**kwargs|
        mutate { app.command(path, :add, type, **prepare(kwargs)) }
      end
    end

    # Insert an entry at a specific index, shifting later entries down.
    # @param index [Integer, Symbol, String] Tk entry index (or :end)
    # @param type [Symbol] one of {ENTRY_TYPES}
    # @param kwargs entry options (e.g. label:, command:)
    # @return [self]
    def insert(index, type, **kwargs)
      mutate { app.command(path, :insert, index, type, **prepare(kwargs)) }
    end

    # Reconfigure an existing entry in place.
    # @param index [Integer, Symbol, String] Tk entry index (or :end)
    # @param kwargs entry options to change (e.g. label:, command:)
    # @return [self]
    def entryconfigure(index, **kwargs)
      mutate { app.command(path, :entryconfigure, index, **prepare(kwargs)) }
    end

    # Delete one entry, or an inclusive range of entries.
    # @param first [Integer, Symbol, String] first index (or :end)
    # @param last [Integer, Symbol, String, nil] last index (or :end); omit to delete only +first+
    # @return [self]
    def delete(first, last = nil)
      args = last.nil? ? [first] : [first, last]
      mutate { app.command(path, :delete, *args) }
    end

    # Remove all entries.
    # @return [self]
    def clear
      delete(0, :end) unless empty?
      self
    end

    # @return [Boolean] true if the menu has no entries
    def empty?
      app.tcl_eval("#{path} index end") == 'none'
    end

    # Post this menu as a popup at the given screen coordinates.
    # @param x [Integer] screen x coordinate
    # @param y [Integer] screen y coordinate
    # @return [void]
    def popup(x, y)
      app.tcl_eval("tk_popup #{path} #{x} #{y}")
    end

    private

    # Registers a Proc passed as `command:` and swaps it for the literal
    # Tcl script App#command will brace-quote, so the entry ends up with
    # the same `-command {ruby_callback cbN}` shape #bind produces - which
    # is what {#live_command_ids} looks for via entrycget.
    def prepare(kwargs)
      return kwargs unless kwargs[:command].is_a?(Proc)
      # A menu entry's command is invoked as a plain script, not through
      # Tk's bind dispatch - see App#register_callback's note on why
      # break/continue can't be relayed there.
      id = app.register_callback(kwargs[:command], relay_break_continue: false)
      kwargs.merge(command: "ruby_callback #{id}")
    end

    def mutate
      yield
      app.callback_registry.reconcile([:menu, path]) { |_before| live_command_ids }
      self
    end

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

    def live_command_ids
      app.ensure_tcl_helper(:menu_live_commands) { LIVE_COMMANDS_TCL_PROC }
      raw = app.tcl_eval("::teek_menu_live_commands #{path}")
      app.split_list(raw).each_with_object({}) do |cmd, ids|
        if (m = cmd.match(/\Aruby_callback (\S+)\z/))
          ids[m[1]] = m[1]
        end
      end
    end
  end

  Widget.register_behavior('menu', MenuBehavior)
end
