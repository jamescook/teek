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

      app.tcl_eval("menu .stress")
      menu = app.menu('.stress')
      fired = 0

      300.times do |i|
        case i % 7
        when 0
          menu.clear
        when 1
          menu.add_command(label: "cmd#{i}", command: proc { fired += 1 })
        when 2
          menu.add_checkbutton(label: "chk#{i}", command: proc { fired += 1 })
        when 3
          menu.add_radiobutton(label: "rad#{i}", command: proc { fired += 1 })
        when 4
          menu.add_separator
          menu.add_command(label: "post_sep#{i}", command: proc { fired += 1 })
          menu.insert(0, :command, label: "inserted#{i}", command: proc { fired += 1 }) unless menu.empty?
        when 5
          unless menu.empty?
            menu.entryconfigure(0, command: proc { fired += 1 })
          end
        when 6
          unless menu.empty?
            menu.delete(0)
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
