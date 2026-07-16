#!/usr/bin/env ruby
# frozen_string_literal: true
# teek-record: title=Tk Goldberg (teek-ui)

# Goldberg demo - full teek-ui DSL port
#
# Ports sample/goldberg.rb's canvas/physics demo (a Rube Goldberg machine
# animation) onto the teek-ui DSL: the control panel below builds real
# widgets and reactive vars the same way any other teek-ui app does; the
# canvas drawing/animation itself is driven by GoldbergEngine (see
# sample/goldberg_engine.rb), which calls straight into Handle's canvas
# item methods (line/oval/polygon/arc/rectangle/text/bitmap, CanvasItem's
# move/coords/scale/configure/...) - no raw tcl_eval except the couple of
# genuine DSL gaps noted inline (a named bold font, the initial canvas
# scroll position).
#
# Run: ruby sample/goldberg_ui.rb

# Load the local checkouts, not whatever teek/teek-ui gems happen to be
# installed - same reasoning as sample/paint/paint_demo.rb.
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
$LOAD_PATH.unshift(File.expand_path('../teek-ui/lib', __dir__))
require 'teek/ui'
require_relative 'goldberg_engine'
require_relative '../lib/teek/demo_support'

BG = 'cornflowerblue'
FG = 'black'

INFO_TEXT = "This is a demonstration of just how complex you can make your animations become. " \
            "Click the ball to start things moving!\n" \
            "\"Man will always find a difficult means to perform a simple task\" - Rube Goldberg"

vars = {}
engine = nil

session = Teek::UI.app(title: 'Tk Goldberg (teek-ui)') do |ui|
  vars[:status] = ui.var('Ready')
  vars[:pause] = ui.var(false)
  vars[:details] = ui.var(true)
  vars[:message] = ui.var('\nWelcome\nto\nRuby/Tk')
  vars[:speed] = ui.var(5)
  vars[:cnt] = ui.var(0)
  vars[:step_vars] = {}
  (1..26).each { |idx| vars[:step_vars][idx] = ui.var(0) }

  do_button = ->(n) { engine.do_button(n) }
  reset = -> { engine.reset }
  show_about = -> { engine.about }

  toggle_ctrl = lambda {
    ctrl_path = ui[:ctrl].path
    if ui.app.winfo.ismapped?(ctrl_path)
      ui.app.command(:pack, :forget, ctrl_path)
      ui[:show_ctrl_btn].configure(text: '>>')
    else
      ui.app.command(:pack, ctrl_path, side: :right, fill: :both, ipady: 5)
      ui[:show_ctrl_btn].configure(text: '<<')
    end
  }

  # A bold variant of the default UI font, scoped to the Start button
  # only - no DSL equivalent for "inherit the running default font, just
  # bold it", and ttk::button doesn't expose -font as a direct widget
  # option at all (style-only), so this stays a direct escape-hatch
  # font-create + a one-off ttk style, same spirit as goldberg.rb's own
  # font-create technique.
  ui.raw { |app|
    app.tcl_eval('font create GoldbergBold {*}[font configure TkDefaultFont] -weight bold')
    app.tcl_eval('ttk::style configure Bold.TButton -font GoldbergBold')
  }

  ui.menu_bar do |mb|
    mb.menu(label: 'File') do |file|
      file.item(label: 'Reset') { reset.call }
      file.separator
      file.item(label: 'Quit') { ui.app.destroy }
    end
    mb.menu(label: 'Edit') do |edit|
      edit.checkbox(label: 'Details', bind: vars[:details]).on_click { engine.active_GUI }
    end
    mb.menu(label: 'Help') do |help|
      help.item(label: 'About') { show_about.call }
    end
  end

  ui.row(:layout) do |m|
    m.canvas(:board, grow: true, width: 850, height: 700,
             background: BG, highlightthickness: 0, scrollregion: [0, 0, 1000, 1000]) do |cv|
      cv.overlay(at: :top_right) do
        cv.row(gap: 0) do |r|
          r.button(:dismiss, text: 'Dismiss').on_click { ui.app.destroy }
          r.button(:show_ctrl_btn, text: '>>').on_click { toggle_ctrl.call }
        end
      end
    end

    m.column(:ctrl, gap: 4, align: :stretch, relief: 'ridge', borderwidth: 2, padding: [5, 5]) do |ctrl|
      ctrl.button(:start, text: 'Start', style: 'Bold.TButton').on_click { do_button.call(0) }

      ctrl.checkbox(:pause, text: 'Pause', bind: vars[:pause]).on_click { do_button.call(1) }
      ctrl.button(:step, text: 'Single Step').on_click { do_button.call(2) }
      ctrl.button(:bstep, text: 'Big Step').on_click { do_button.call(4) }
      ctrl.button(:reset, text: 'Reset').on_click { do_button.call(3) }

      ctrl.column(:details_frame, gap: 0, align: :stretch, relief: 'ridge', borderwidth: 2) do |df|
        df.checkbox(:details, text: 'Details', bind: vars[:details]).on_click { engine.active_GUI }

        df.grid(:detail_grid) do |g|
          g.cell(row: 0, col: 0, span: 4) { g.label(bind: vars[:cnt], relief: 'solid', borderwidth: 1, background: 'white') }

          (1..26).each { |idx|
            row = (idx + 1) / 2
            col = ((idx + 1) & 1) * 2
            g.cell(row: row, col: col) {
              g.label(text: idx.to_s, anchor: :e, width: 2, relief: 'solid', borderwidth: 1, background: 'white')
            }
            g.cell(row: row, col: col + 1) {
              g.label(bind: vars[:step_vars][idx], width: 5, relief: 'solid', borderwidth: 1, background: 'white')
            }
          }
        end
      end

      ctrl.spacer

      ctrl.text_box(:msg_entry, bind: vars[:message], justify: :center)

      ctrl.row(:speed_row, gap: 6, align: :center) do |r|
        r.label(text: 'Speed:')
        r.label(:speed_value, bind: vars[:speed])
        r.slider(:speed_scale, from: 1, to: 10, bind: vars[:speed])
      end

      ctrl.button(:about, text: 'About').on_click { show_about.call }
    end
  end
end

session.run_async

# The info message, in the canvas's own top-left corner. A classic (not
# ttk) label, matching goldberg.rb's own choice here - ttk::label accepts
# -background without error, but under macOS's Aqua theme it's silently
# ignored at render time, leaving the theme's own light background
# showing through instead of matching the canvas. A plain Tk label has no
# theme to fight, so -bg always applies. No DSL widget type for a
# non-ttk label, so this is a direct escape-hatch creation + place,
# reusing the same anchor math ui.overlay's own :top_left anchor uses.
board_path = session[:board].path
msg_path = "#{board_path}.msg"
session.app.tcl_eval(
  "label #{msg_path} -bg #{BG} -fg white -font {Arial 10} -wraplength 600 " \
  "-justify left -text {#{INFO_TEXT}}"
)
session.app.command(:place, msg_path, in: board_path, relx: 0, rely: 0, anchor: :nw)

# No DSL equivalent for an initial canvas scroll position - a one-line
# escape hatch, same as goldberg.rb's own `yview moveto`.
session.app.tcl_eval("#{board_path} yview moveto 0.05")

# The control panel starts collapsed, exactly like goldberg.rb's own
# @ctrl (built but never packed until the >> button first shows it) -
# done right after realize/show, before anything is painted, so there's
# no visible flash of it being shown then immediately hidden.
session.app.command(:pack, :forget, session[:ctrl].path)

engine = GoldbergEngine.new(session, session[:board], vars)

TeekDemo.app = session.app

if TeekDemo.recording?
  session.app.set_window_geometry('+0+0')
  session.app.tcl_eval('. configure -cursor none')
  TeekDemo.signal_recording_ready
  session.app.after(500) { engine.start }
elsif TeekDemo.testing?
  TeekDemo.after_idle {
    session[:show_ctrl_btn].configure(text: '>>')
    session.app.command(:pack, session[:ctrl].path, side: :right, fill: :both, ipady: 5)
    session.app.update

    session.app.command(session[:speed_scale].path, :set, 1)
    session.app.update

    session.app.command(session[:start].path, :invoke)

    session.app.after(2000) { TeekDemo.finish }
  }
end

session.app.mainloop
