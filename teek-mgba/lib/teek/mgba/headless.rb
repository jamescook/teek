# frozen_string_literal: true

# Lightweight entry point for headless (no GUI) usage of teek-mgba.
# Loads only the C extension and pure-Ruby modules — no Tk, no SDL2.
#
#   require "teek/mgba/headless"
#   Teek::MGBA::HeadlessPlayer.open("game.gba") { |p| p.step(60) }

require_relative "runtime"
require_relative "recorder"
require_relative "recorder_decoder"
require_relative "headless_player"
