# frozen_string_literal: true

# Generates a recordings.html page listing all demo videos.
# Run: ruby docs_site/build_recordings.rb

require 'erb'
require 'fileutils'

class RecordingsBuilder
  TEMPLATES_DIR = File.join(__dir__, 'templates')
  OUTPUT_DIR = __dir__
  ASSETS_DIR = File.join(__dir__, 'assets', 'recordings')
  SAMPLE_DIR = File.expand_path('../sample', __dir__)

  MIME_TYPES = {
    '.mp4' => 'video/mp4',
    '.webm' => 'video/webm',
  }.freeze

  def build
    videos = Dir.glob(File.join(ASSETS_DIR, '*.{mp4,webm}')).sort
    if videos.empty?
      puts "No recordings found in #{ASSETS_DIR}"
      return
    end

    titles = extract_titles

    recordings = videos.map do |path|
      filename = File.basename(path)
      ext = File.extname(filename)
      stem = File.basename(filename, ext)

      {
        filename: filename,
        title: titles[stem] || stem.tr('_', ' ').capitalize,
        mime: MIME_TYPES[ext] || 'video/mp4',
      }
    end

    template = ERB.new(File.read(File.join(TEMPLATES_DIR, 'recordings.html.erb')), trim_mode: '-')
    content = template.result(binding)
    output_path = File.join(OUTPUT_DIR, 'recordings.html')
    File.write(output_path, content)

    puts "Generated #{output_path} (#{recordings.size} video#{'s' if recordings.size != 1})"
  end

  private

  # Extract titles from teek-record magic comments in sample files
  def extract_titles
    titles = {}
    Dir.glob(File.join(SAMPLE_DIR, '**/*.rb')).each do |path|
      first_lines = File.read(path, 500)
      match = first_lines.match(/^#\s*teek-record(?::\s*(.+))?$/)
      next unless match

      stem = File.basename(path, '.rb')
      if match[1]
        match[1].split(',').each do |pair|
          key, value = pair.strip.split('=', 2)
          titles[stem] = value.strip if key.strip == 'title' && value
        end
      end
    end
    titles
  end
end

if __FILE__ == $0
  RecordingsBuilder.new.build
end
