# frozen_string_literal: true

require 'fileutils'

module Teek
  module MGBA
    # Resolves ROM paths for the player. Handles both bare ROM files
    # and .zip archives containing a single ROM at the zip root.
    #
    # @example Load a bare ROM
    #   path = RomLoader.resolve("/path/to/game.gba")
    #   # => "/path/to/game.gba"
    #
    # @example Load from a zip
    #   path = RomLoader.resolve("/path/to/game.zip")
    #   # => "/Users/you/.config/teek-mgba/tmp/game.gba"
    class RomLoader
      ROM_EXTENSIONS = %w[.gba .gb .gbc].freeze
      ZIP_EXTENSIONS = %w[.zip].freeze
      SUPPORTED_EXTENSIONS = (ROM_EXTENSIONS + ZIP_EXTENSIONS).freeze

      class Error < StandardError; end
      class NoRomInZip < Error; end
      class MultipleRomsInZip < Error; end
      class UnsupportedFormat < Error; end
      class ZipReadError < Error; end

      # Resolve a path to a loadable ROM file.
      # For ROM files, returns the path unchanged.
      # For ZIP files, extracts the single ROM inside to a temp directory.
      #
      # @param path [String] path to a ROM or ZIP file
      # @return [String] path to a loadable ROM file
      # @raise [NoRomInZip] if the ZIP contains no ROM files at the root
      # @raise [MultipleRomsInZip] if the ZIP contains more than one ROM
      # @raise [UnsupportedFormat] if the file extension is not supported
      # @raise [ZipReadError] if the ZIP file cannot be read
      def self.resolve(path)
        ext = File.extname(path).downcase
        if ROM_EXTENSIONS.include?(ext)
          path
        elsif ZIP_EXTENSIONS.include?(ext)
          begin
            require 'zip'
          rescue LoadError
            raise ZipReadError, "rubyzip gem not available (gem install rubyzip)"
          end
          extract_from_zip(path)
        else
          raise UnsupportedFormat, ext
        end
      end

      # Remove previously extracted temp files.
      def self.cleanup_temp
        dir = tmp_dir
        FileUtils.rm_rf(dir) if File.directory?(dir)
      end

      # @return [String] temp directory for extracted ROMs
      def self.tmp_dir
        File.join(Config.config_dir, 'tmp')
      end

      # Extract the single ROM from a ZIP file.
      # Only considers entries at the zip root (no subdirectories).
      # @param zip_path [String]
      # @return [String] path to extracted ROM
      def self.extract_from_zip(zip_path)
        basename = File.basename(zip_path)
        roms = []

        Zip::File.open(zip_path) do |zip|
          zip.each do |entry|
            next if entry.directory?
            next if entry.name.include?('/')
            if ROM_EXTENSIONS.include?(File.extname(entry.name).downcase)
              roms << entry
            end
          end

          raise NoRomInZip, basename if roms.empty?
          raise MultipleRomsInZip, basename if roms.length > 1

          rom_entry = roms.first
          dir = tmp_dir
          FileUtils.mkdir_p(dir)
          out_path = File.join(dir, File.basename(rom_entry.name))
          File.binwrite(out_path, rom_entry.get_input_stream.read)
          out_path
        end
      rescue NoRomInZip, MultipleRomsInZip
        raise
      rescue Zip::Error => e
        raise ZipReadError, "#{basename}: #{e.message}"
      rescue => e
        raise ZipReadError, "#{basename}: #{e.message}"
      end
      private_class_method :extract_from_zip
    end
  end
end
