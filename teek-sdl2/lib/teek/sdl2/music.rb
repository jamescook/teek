# frozen_string_literal: true

module Teek
  module SDL2
    # Streaming music playback for longer audio files (MP3, OGG, WAV).
    #
    # Only one Music track can play at a time (SDL2_mixer limitation).
    # For short sound effects that can overlap, use {Sound} instead.
    #
    # @example
    #   music = Teek::SDL2::Music.new("background.mp3")
    #   music.play              # loops forever by default
    #   music.volume = 64       # half volume
    #   music.pause
    #   music.resume
    #   music.stop
    #   music.destroy
    class Music
    end
  end
end
