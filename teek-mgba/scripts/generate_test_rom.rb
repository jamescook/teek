#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates a minimal valid GBA ROM for testing teek-mgba.
#
# The ROM contains a valid GBA header (entry branch, title, fixed byte,
# complement checksum) and an ARM infinite loop. mGBA will load it,
# emulate frames, and produce video/audio output — enough to exercise
# every Core method without needing a real game.
#
# GBA cartridge header reference (all offsets below):
#   https://problemkaputt.de/gbatek-gba-cartridge-header.htm
#
# Usage:
#   ruby teek-mgba/scripts/generate_test_rom.rb
#
# Output:
#   teek-mgba/test/fixtures/test.gba

rom = ("\x00".b) * 512

# 0x00: ARM entry point — branch to 0x08000020 (6 words forward, PC+8 pipeline)
rom[0, 4] = [0xEA000006].pack("V")

# 0x20: ARM `b .` (branch to self — infinite loop)
rom[0x20, 4] = [0xEAFFFFFE].pack("V")

# 0xA0..0xAB: Game title (12 bytes, padded with NUL)
rom[0xA0, 12] = "TEEKTEST".ljust(12, "\x00")

# 0xAC..0xAF: Game code (B=GBA, TK=Teek, E=English)
rom[0xAC, 4] = "BTKE"

# 0xB0..0xB1: Maker code
rom[0xB0, 2] = "01"

# 0xB2: Fixed value — BIOS rejects the ROM if this isn't 0x96
rom.setbyte(0xB2, 0x96)

# 0xBD: Header complement checksum — sum of bytes 0xA0..0xBC,
# then chk = -(sum + 0x19) & 0xFF. BIOS verifies this on boot.
sum = (0xA0..0xBC).sum { |i| rom.getbyte(i) }
rom.setbyte(0xBD, (-(sum + 0x19)) & 0xFF)

out = File.expand_path("../test/fixtures/test.gba", __dir__)
File.binwrite(out, rom)
puts "Wrote #{rom.bytesize} bytes to #{out}"
