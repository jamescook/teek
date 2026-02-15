# frozen_string_literal: true

require 'optparse'
require_relative 'version'

module Teek
  module MGBA
    class CLI
      # Parse command-line arguments into an options hash.
      # @param argv [Array<String>]
      # @return [Hash] parsed options
      def self.parse(argv)
        options = {}

        parser = OptionParser.new do |o|
          o.banner = "Usage: teek-mgba [options] [ROM_FILE]"
          o.separator ""
          o.separator "GBA emulator powered by teek + libmgba"
          o.separator ""
          o.separator "Options:"

          o.on("-s", "--scale N", Integer, "Window scale (1-4)") do |v|
            options[:scale] = v.clamp(1, 4)
          end

          o.on("-v", "--volume N", Integer, "Volume (0-100)") do |v|
            options[:volume] = v.clamp(0, 100)
          end

          o.on("-m", "--mute", "Start muted") do
            options[:mute] = true
          end

          o.on("--no-sound", "Disable audio entirely") do
            options[:sound] = false
          end

          o.on("-f", "--fullscreen", "Start in fullscreen") do
            options[:fullscreen] = true
          end

          o.on("--show-fps", "Show FPS counter") do
            options[:show_fps] = true
          end

          o.on("--turbo-speed N", Integer, "Fast-forward speed (0=uncapped, 2-4)") do |v|
            options[:turbo_speed] = v.clamp(0, 4)
          end

          o.on("--locale LANG", "Language (en, ja, auto)") do |v|
            options[:locale] = v
          end

          o.on("--version", "Show version") do
            options[:version] = true
          end

          o.on("-h", "--help", "Show this help") do
            options[:help] = true
          end
        end

        parser.parse!(argv)
        options[:rom] = argv.first
        options[:parser] = parser
        options
      end

      # Apply parsed CLI options to the user config (session-only overrides).
      # @param config [Teek::MGBA::Config]
      # @param options [Hash]
      def self.apply(config, options)
        config.scale = options[:scale] if options[:scale]
        config.volume = options[:volume] if options[:volume]
        config.muted = true if options[:mute]
        config.show_fps = true if options[:show_fps]
        config.turbo_speed = options[:turbo_speed] if options[:turbo_speed]
        config.locale = options[:locale] if options[:locale]
      end

      # Entry point: parse argv, apply config overrides, launch player.
      # @param argv [Array<String>]
      def self.run(argv = ARGV)
        options = parse(argv.dup)

        if options[:help]
          puts options[:parser]
          return
        end

        if options[:version]
          puts "teek-mgba #{Teek::MGBA::VERSION}"
          return
        end

        require "teek/mgba"

        apply(Teek::MGBA.user_config, options)
        Teek::MGBA.load_locale if options[:locale]

        sound = options.fetch(:sound, true)
        Player.new(options[:rom], sound: sound, fullscreen: options[:fullscreen]).run
      end
    end
  end
end
