#!/usr/bin/env ruby
# frozen_string_literal: true
# teek-record: title=Goldberg Control Panel (teek-ui)

# Goldberg Control Panel - teek-ui DSL port (phase 1 proof)
#
# Ports goldberg.rb's control panel (do_ctrl_frame - the column of Start/
# Pause/Step/Big Step/Reset/Details/spacer/message/speed/About) to the
# teek-ui DSL, to see whether the retained-mode (build -> realize) concept
# actually works end to end against a real, representative screen before
# building further on it. This is a starting point, not a full port of
# goldberg's physics simulation - see sample/goldberg.rb for the original.
#
# Run: ruby sample/goldberg_ui.rb

# Load the local checkouts, not whatever teek/teek-ui gems happen to be
# installed - same reasoning as sample/paint/paint_demo.rb.
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
$LOAD_PATH.unshift(File.expand_path('../teek-ui/lib', __dir__))
require 'teek/ui'

Teek::UI.app(title: 'Goldberg Control Panel (teek-ui)') do |ui|
  mode = ui.var('Ready')
  pause = ui.var(false)
  details = ui.var(false)
  message = ui.var('')
  speed = ui.var(5)

  ui.column(:root, gap: 10, align: :stretch, pad: 10) do |c|
    c.label(:status, bind: mode)
    c.divider

    c.column(:ctrl, gap: 4, align: :stretch) do |ctrl|
      ctrl.button(:start, text: 'Start').on_click { mode.value = 'Running' }

      ctrl.checkbox(:pause, text: 'Pause', bind: pause)
        .on_click { mode.value = pause.value ? 'Paused' : 'Running' }

      ctrl.button(:step, text: 'Single Step').on_click { mode.value = 'Stepped' }
      ctrl.button(:bstep, text: 'Big Step').on_click { mode.value = 'Big stepped' }

      ctrl.button(:reset, text: 'Reset').on_click {
        mode.value = 'Ready'
        pause.value = false
        message.value = ''
        speed.value = 5
      }

      ctrl.checkbox(:details, text: 'Details', bind: details)
        .on_click { mode.value = "Details #{details.value ? 'shown' : 'hidden'}" }

      ctrl.spacer

      ctrl.text_box(:msg_entry, bind: message)
        .on_key(:enter) { mode.value = "Message: #{message.value}" }

      ctrl.row(:speed_row, gap: 6, align: :center) do |r|
        r.label(text: 'Speed:')
        r.label(:speed_value, bind: speed)
        r.slider(:speed_scale, from: 1, to: 10, bind: speed)
      end

      ctrl.button(:about, text: 'About').on_click {
        ui.app.message_box(
          title: 'About',
          message: "Goldberg Control Panel (teek-ui port)",
          detail: 'A teek-ui DSL port of goldberg.rb\'s control panel - column/row, ' \
                  'gap/align/spacer, on_click/on_key, and reactive vars, no raw tcl_eval.'
        )
      }
    end
  end
end.run
