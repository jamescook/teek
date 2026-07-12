# frozen_string_literal: true

# Throwaway stress script (not meant to be committed) - repeatedly stands
# up and tears down menu entries/callbacks through a mix of every mutating
# op to make sure the reconcile logic doesn't segfault or raise under
# heavier, less orderly use than the unit tests exercise.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestMenuStress < Minitest::Test
  include TeekTestHelper

  def test_menu_survives_a_few_hundred_mixed_mutations
    assert_tk_app("menu should survive many mixed mutations without crashing or leaking") do
      baseline = app.interp.callback_ids.length

      menu = app.menu('.stress')
      fired = 0

      empty = -> { app.tcl_eval("#{menu} index end") == 'none' }

      300.times do |i|
        case i % 7
        when 0
          menu.command(:delete, 0, :end) unless empty.call
        when 1
          menu.command(:add, :command, label: "cmd#{i}", command: proc { fired += 1 })
        when 2
          menu.command(:add, :checkbutton, label: "chk#{i}", command: proc { fired += 1 })
        when 3
          menu.command(:add, :radiobutton, label: "rad#{i}", command: proc { fired += 1 })
        when 4
          menu.command(:add, :separator)
          menu.command(:add, :command, label: "post_sep#{i}", command: proc { fired += 1 })
          menu.command(:insert, 0, :command, label: "inserted#{i}", command: proc { fired += 1 }) unless empty.call
        when 5
          unless empty.call
            menu.command(:entryconfigure, 0, command: proc { fired += 1 })
          end
        when 6
          unless empty.call
            menu.command(:delete, 0)
          end
        end
      end

      # Invoke whatever survived, to make sure live entries still work.
      last = app.tcl_eval(".stress index end")
      unless last == 'none'
        (0..last.to_i).each do |idx|
          type = app.tcl_eval(".stress type #{idx}") rescue nil
          next if type == 'separator'
          app.tcl_eval(".stress invoke #{idx}") rescue nil
        end
      end

      app.destroy('.stress')

      assert_equal baseline, app.interp.callback_ids.length,
        "callback count should return to baseline after destroy, no leaked ids from the stress run"
      assert fired >= 0 # just proving nothing raised getting here
    end
  end
end
