# frozen_string_literal: true

# == xvfb gotcha: focus & key events ==
#
# Under xvfb, `event generate <widget> <KeyPress>` only fires bindings
# when the widget has focus. The first key event after poll_until_ready
# usually works, but inside nested `app.after` callbacks focus can drift.
# If a second (or later) key event silently does nothing, add:
#
#   app.tcl_eval("focus -force #{frame}")
#
# before the `event generate` call. See test_recording_toggle for an example.

# Polls `tk busy status .` until the Player finishes SDL2 init
# (viewport, audio, renderer), then yields the block.
#
# The Player sets `tk busy .` before init and clears it after,
# so this fires as soon as the player is actually ready — no
# speculative sleeps.
#
# @param app [Teek::App]
# @param timeout_ms [Integer] max wait before aborting (default 10s)
def poll_until_ready(app, timeout_ms: 10_000, &block)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_ms / 1000.0
  check = proc do
    if app.tcl_eval("tk busy status .") == "0"
      block.call
    elsif Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      $stderr.puts "FAIL: Player not ready within #{timeout_ms}ms"
      exit 1
    else
      app.after(50, &check)
    end
  end
  app.after(50, &check)
end
