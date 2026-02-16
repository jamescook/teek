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

          o.on("--headless", "Run without GUI (no Tk/SDL2, requires ROM)") do
            options[:headless] = true
          end

          o.on("--frames N", Integer, "Run N frames then exit (requires ROM)") do |v|
            options[:frames] = v
          end

          o.on("--reset-config", "Delete settings file and exit (keeps saves)") do
            options[:reset_config] = true
          end

          o.on("-y", "--yes", "Skip confirmation prompts") do
            options[:yes] = true
          end

          o.on("--version", "Show version") do
            options[:version] = true
          end

          o.on("-h", "--help", "Show this help") do
            options[:help] = true
          end
        end

        parser.parse!(argv)
        options[:rom] = File.expand_path(argv.first) if argv.first
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

        if options[:headless]
          return run_headless(options)
        end

        require "teek/mgba"

        if options[:reset_config]
          path = Config.default_path
          unless File.exist?(path)
            puts "No config file found at #{path}"
            return
          end
          unless options[:yes]
            print "Delete #{path}? [y/N] "
            return unless $stdin.gets&.strip&.downcase == 'y'
          end
          Config.reset!(path: path)
          puts "Deleted #{path}"
          return
        end

        if options[:frames] && !options[:rom]
          $stderr.puts "Error: --frames requires a ROM file"
          exit 1
        end

        apply(Teek::MGBA.user_config, options)
        Teek::MGBA.load_locale if options[:locale]

        sound = options.fetch(:sound, true)
        Player.new(options[:rom], sound: sound, fullscreen: options[:fullscreen],
                   frames: options[:frames]).run
      end

      # Run in headless mode: no Tk, no SDL2. Batch only — runs N frames and exits.
      # @param options [Hash]
      def self.run_headless(options)
        unless options[:frames] && options[:rom]
          $stderr.puts "Error: --headless requires --frames N and a ROM file"
          exit 1
        end

        require "teek/mgba/headless"

        HeadlessPlayer.open(options[:rom]) do |player|
          player.step(options[:frames])
        end
      end
      private_class_method :run_headless
    end
  end
end
