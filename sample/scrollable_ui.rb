#!/usr/bin/env ruby
# frozen_string_literal: true
# teek-record: title=Scrollable Regions (teek-ui)

# Scrollable Regions - teek-ui DSL demo
#
# Demonstrates ui.scrollable, which auto-wires a working ttk::scrollbar to
# its content with zero -yscrollcommand/-xscrollcommand/scrollbar-widget
# code in the app itself (see teek-ui/README.md's "Scrolling" section):
#
#   - a scrollable listbox (the "native" case - the scrollbar hooks
#     straight into the widget's own yview/-yscrollcommand protocol)
#   - a scrollable column of checkboxes (the "frame" case - there's no Tk
#     scrolling protocol for a frame full of arbitrary widgets, so it's
#     wrapped in an embedded canvas viewport instead, transparently)
#
# Run: ruby sample/scrollable_ui.rb

# Load the local checkouts, not whatever teek/teek-ui gems happen to be
# installed - same reasoning as sample/paint/paint_demo.rb.
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
$LOAD_PATH.unshift(File.expand_path('../teek-ui/lib', __dir__))
require 'teek/ui'

FRUITS = %w[
  Apple Apricot Banana Blackberry Blueberry Cantaloupe Cherry Clementine
  Coconut Cranberry Date Dragonfruit Elderberry Fig Grape Grapefruit
  Guava Honeydew Jackfruit Kiwi Kumquat Lemon Lime Lychee Mandarin
  Mango Melon Mulberry Nectarine Orange Papaya Passionfruit Peach Pear
  Persimmon Pineapple Plum Pomegranate Quince Raspberry Starfruit
  Strawberry Tangerine Watermelon
].freeze

Teek::UI.app(title: 'Scrollable Regions (teek-ui)') do |ui|
  ui.row(gap: 16, pad: 12) do |r|
    r.column(gap: 6) do |c|
      c.label(text: 'Scrollable list (native)')
      c.scrollable { |s| s.list(:fruit_list, height: 14) }
    end

    r.column(gap: 6, grow: true, align: :stretch) do |c|
      c.label(text: 'Scrollable panel (arbitrary content)')
      c.scrollable(grow: true) do |s|
        s.column(gap: 4, pad: 8) { |col| FRUITS.each { |fruit| col.checkbox(text: fruit) } }
      end
    end
  end

  ui.raw do |app|
    app.set_window_geometry('640x420')
    app.command(ui[:fruit_list].path, :insert, :end, *FRUITS)
  end
end.run
