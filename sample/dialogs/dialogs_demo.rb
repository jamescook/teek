#!/usr/bin/env ruby
# frozen_string_literal: true
# teek-record: title=Dialog Wrappers Demo

# Dialog Wrappers Demo - exercises every safe Tk dialog wrapper
# (choose_open_file, choose_save_file, message_box, choose_color,
# popup_menu) so a human can click through each one and visually
# confirm it opens correctly and the wrapper reports back the right
# result.
#
# Not a "real" app - this is a manual test harness for
# App#choose_open_file / #choose_save_file / #message_box /
# #choose_color / #popup_menu, built specifically to exercise options
# containing spaces (try picking/typing a filename like "my file.png")
# and to show multi-pattern filetypes work.
#
# Run: ruby -Ilib sample/dialogs/dialogs_demo.rb

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'teek'

class DialogsDemo
  attr_reader :app

  def initialize
    @app = Teek::App.new(title: 'Dialog Wrappers Demo')
    @app.set_window_geometry('480x360')
    build_ui
  end

  def run
    @app.show
    @app.mainloop
  end

  private

  def build_ui
    instructions = @app.create_widget('ttk::label',
      text: "Click each button below, then try options with spaces in them\n" \
            "(a filename, a title...) to confirm nothing gets mangled.\n" \
            "Right-click anywhere below the buttons for the popup menu.",
      justify: :left)
    instructions.pack(side: :top, fill: :x, padx: 8, pady: 8)

    buttons = @app.create_widget('ttk::frame')
    buttons.pack(side: :top, fill: :x, padx: 8, pady: 4)

    add_button(buttons, 'Choose Open File...') { demo_choose_open_file }
    add_button(buttons, 'Choose Save File...') { demo_choose_save_file }
    add_button(buttons, 'Message Box...') { demo_message_box }
    add_button(buttons, 'Choose Color...') { demo_choose_color }
    add_button(buttons, 'Popup Menu...') { demo_popup_menu }

    @log = @app.create_widget(:text, height: 10, wrap: :word, state: :disabled)
    @log.pack(side: :bottom, fill: :both, expand: 1, padx: 8, pady: 8)

    build_context_menu
    @app.bind(@log, '<Button-3>') { demo_popup_menu }
  end

  def add_button(parent, label, &block)
    btn = @app.create_widget('ttk::button', text: label, command: block)
    btn.pack(side: :top, fill: :x, padx: 4, pady: 2)
  end

  def build_context_menu
    @context_menu = @app.menu('.dialogs_demo_ctx')
    @context_menu.command(:add, :command, label: 'Say Hello',
      command: proc { log('popup_menu entry chosen -> Say Hello') })
    @context_menu.command(:add, :command, label: 'Say Goodbye',
      command: proc { log('popup_menu entry chosen -> Say Goodbye') })
    @context_menu.command(:add, :separator)
    @context_menu.command(:add, :command, label: '(just closes the menu)', command: proc { })
  end

  def demo_choose_open_file
    result = @app.choose_open_file(
      title: 'Choose a file to open (try one with spaces in the name)',
      filetypes: [['Images', ['.png', '.jpg', '.gif']], ['Text Files', '.txt'], ['All Files', '*']]
    )
    log("choose_open_file -> #{result.inspect}")
  end

  def demo_choose_save_file
    result = @app.choose_save_file(
      title: 'Choose where to save',
      initialfile: 'my file.txt',
      filetypes: [['Text Files', '.txt'], ['All Files', '*']]
    )
    log("choose_save_file -> #{result.inspect}")
  end

  def demo_message_box
    result = @app.message_box(
      message: 'This message box was shown via App#message_box.',
      detail: 'It safely passes {braces} and spaces through - no manual quoting needed.',
      title: 'Confirm',
      icon: :question,
      type: :yesnocancel
    )
    log("message_box -> #{result.inspect}")
  end

  def demo_choose_color
    result = @app.choose_color(initial: '#3366ff', title: 'Pick a } color')
    log("choose_color -> #{result.inspect}")
  end

  def demo_popup_menu
    x = @app.winfo.pointerx
    y = @app.winfo.pointery
    @app.popup_menu(@context_menu, x: x, y: y)
    log("popup_menu shown at #{x},#{y}")
  end

  def log(message)
    @log.command(:configure, state: :normal)
    @log.command(:insert, :end, "#{message}\n")
    @log.command(:see, :end)
    @log.command(:configure, state: :disabled)
  end
end

demo = DialogsDemo.new

# Automated smoke-test support: just confirms the window comes up and
# doesn't crash. The dialogs themselves need a human - see the header.
require_relative '../../lib/teek/demo_support'
TeekDemo.app = demo.app

if TeekDemo.active?
  TeekDemo.on_visible {
    demo.app.after(TeekDemo.delay(test: 200, record: 500)) { TeekDemo.finish }
  }
end

demo.run
