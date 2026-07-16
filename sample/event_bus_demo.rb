#!/usr/bin/env ruby
# frozen_string_literal: true
# teek-record: title=Event Bus Demo (teek-ui)

# Event Bus Demo - ui.on/ui.emit for decoupled widgets
#
# Three independent panels (a cart item-count badge, a running total, and
# an activity log) all react to the same :item_added event, with zero
# direct references between any of them - the product buttons that emit
# it don't know, or care, who's listening.
#
# THE MESS THIS AVOIDS: without a bus, making all three react to "add to
# cart" would mean the buttons' own click handler holding a direct
# reference to each one:
#
#   add_button.on_click {
#     ui[:cart_badge].configure(text: "#{count += 1} items")
#     ui[:cart_total].configure(text: "$#{total += product[:price]}")
#     log_line("Added #{product[:name]}")
#     # ...and every NEW listener means editing this handler again, even
#     # though "sell a product" has nothing conceptually to do with a
#     # badge, a total, or a log.
#   }
#
# ui.on/ui.emit decouples it instead: the button emits one event and
# never has to know who's listening, or how many. Also app-scoped, not a
# global/module-level singleton - two separate Teek::UI.app instances in
# the same process never share a bus (see teek-ui/test/test_event_bus.rb).
#
# Run: ruby sample/event_bus_demo.rb

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
$LOAD_PATH.unshift(File.expand_path('../teek-ui/lib', __dir__))
require 'teek/ui'

PRODUCTS = [
  { name: 'Coffee', price: 4 },
  { name: 'Bagel', price: 3 },
  { name: 'Muffin', price: 5 },
].freeze

def log_line(ui, message)
  log = ui[:log]
  log.configure(state: :normal)
  ui.app.command(log.path, :insert, :end, "#{message}\n")
  ui.app.command(log.path, :see, :end)
  log.configure(state: :disabled)
end

Teek::UI.app(title: 'Event Bus Demo (teek-ui)') do |ui|
  ui.column(gap: 12, pad: 12, align: :stretch) do |c|
    c.row(gap: 24) do |r|
      r.label(text: 'Cart:')
      r.label(:cart_badge, text: '0 items')
      r.label(:cart_total, text: '$0')
    end

    c.label(text: 'Products', justify: :left)
    c.row(gap: 8) do |r|
      PRODUCTS.each do |product|
        r.button(text: "#{product[:name]} ($#{product[:price]})").on_click { ui.emit(:item_added, product) }
      end
    end

    c.label(text: 'Activity Log', justify: :left)
    c.text_area(:log, height: 8, grow: true)
  end

  # Each subscriber is self-contained - none of them knows the others
  # exist, and the buttons above never reference any of them by name.
  count = 0
  ui.on(:item_added) { |_product|
    count += 1
    ui[:cart_badge].configure(text: "#{count} item#{'s' unless count == 1}")
  }

  total = 0
  ui.on(:item_added) { |product|
    total += product[:price]
    ui[:cart_total].configure(text: "$#{total}")
  }

  ui.on(:item_added) { |product| log_line(ui, "Added #{product[:name]} ($#{product[:price]})") }

  ui.raw { |app| app.set_window_geometry('420x360') }
end.run
