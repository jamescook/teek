# frozen_string_literal: true

module Teek
  module SDL2
    # A short audio sample loaded from a WAV file.
    #
    # Sound wraps SDL2_mixer's Mix_Chunk for fire-and-forget playback
    # of sound effects. The audio mixer is initialized automatically
    # on first use.
    #
    # @example
    #   sound = Teek::SDL2::Sound.new("click.wav")
    #   sound.play
    #   sound.play(volume: 64)   # half volume
    #   sound.destroy
    class Sound
    end
  end
end
