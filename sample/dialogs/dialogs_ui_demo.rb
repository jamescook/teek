#!/usr/bin/env ruby
# frozen_string_literal: true
# teek-record: title=Dialog Wrappers Demo (teek-ui)

# Dialog Wrappers Demo - teek-ui DSL version
#
# The DSL companion to sample/dialogs/dialogs_demo.rb - exercises the
# ui.* dialog surface (open_file, save_file, message, choose_color,
# choose_dir) instead of reaching through session.app.choose_open_file
# and friends. These are real native OS dialogs, so this - like the
# core demo it mirrors - needs a human clicking through it; there's no
# way to exercise "does the real dialog appear and report back what I
# picked" headlessly (see test/test_dialogs.rb and teek-ui/test/test_ui.rb
# for what IS covered headlessly: that each ui.* method forwards its
# options to the right underlying Tk command, via a stubbed proc).
#
# Run: ruby sample/dialogs/dialogs_ui_demo.rb

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
$LOAD_PATH.unshift(File.expand_path('../../teek-ui/lib', __dir__))
require 'teek/ui'

def log(ui, message)
  log_widget = ui[:log]
  log_widget.configure(state: :normal)
  ui.app.command(log_widget.path, :insert, :end, "#{message}\n")
  ui.app.command(log_widget.path, :see, :end)
  log_widget.configure(state: :disabled)
end

session = Teek::UI.app(title: 'Dialog Wrappers Demo (teek-ui)') do |ui|
  ui.column(gap: 8, pad: 8, align: :stretch) do |c|
    c.label(
      text: "Click each button below, then try options with spaces in them\n" \
            "(a filename, a title...) to confirm nothing gets mangled.",
      justify: :left
    )

    c.button(text: 'Open File...').on_click {
      result = ui.open_file(
        title: 'Choose a file to open (try one with spaces in the name)',
        filetypes: [['Images', ['.png', '.jpg', '.gif']], ['Text Files', '.txt'], ['All Files', '*']]
      )
      log(ui, "open_file -> #{result.inspect}")
    }

    c.button(text: 'Save File...').on_click {
      result = ui.save_file(title: 'Choose where to save', initialfile: 'my file.txt',
                             filetypes: [['Text Files', '.txt'], ['All Files', '*']])
      log(ui, "save_file -> #{result.inspect}")
    }

    c.button(text: 'Message...').on_click {
      result = ui.message(
        message: 'This message box was shown via ui.message.',
        detail: 'It safely passes {braces} and spaces through - no manual quoting needed.',
        title: 'Confirm', icon: :question, type: :yesnocancel
      )
      log(ui, "message -> #{result.inspect}")
    }

    c.button(text: 'Choose Color...').on_click {
      result = ui.choose_color(initial: '#3366ff', title: 'Pick a } color')
      log(ui, "choose_color -> #{result.inspect}")
    }

    c.button(text: 'Choose Directory...').on_click {
      result = ui.choose_dir(title: 'Pick a folder')
      log(ui, "choose_dir -> #{result.inspect}")
    }

    c.text_area(:log, height: 10, grow: true)
  end

  ui.raw { |app| app.set_window_geometry('480x360') }
end

Teek::UI::TreeInspector.new(session.document).print_tree

session.run
