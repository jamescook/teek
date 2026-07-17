# Clean coverage artifacts before test runs to prevent accumulation
CLEAN.include('coverage/.resultset.json', 'coverage/results')

desc "Clear stale coverage artifacts"
task :clean_coverage do
  require 'fileutils'
  FileUtils.rm_f('coverage/.resultset.json')
  FileUtils.rm_rf('coverage/results')
  FileUtils.mkdir_p('coverage/results')
end

namespace :coverage do
  desc "Collate coverage results from multiple test runs into a single report"
  task :collate do
    require 'simplecov'
    require 'simplecov_json_formatter'
    require_relative '../../test/simplecov_config'

    result_files = Dir['coverage/results/*/.resultset.json']
    if result_files.empty?
      puts "No coverage results found in coverage/results/"
      next
    end

    puts "Collating coverage from: #{result_files.map { |f| File.dirname(f).split('/').last }.join(', ')}"

    SimpleCov.collate(result_files) do
      coverage_dir 'coverage'
      formatter SimpleCov::Formatter::MultiFormatter.new([
        SimpleCov::Formatter::HTMLFormatter,
        SimpleCov::Formatter::JSONFormatter
      ])
      SimpleCovConfig.apply_filters(self)
      SimpleCovConfig.apply_groups(self)
    end

    puts "Coverage report generated: coverage/index.html, coverage/coverage.json"
  end

  desc "Full coverage pipeline: collate results"
  task :full => :collate
end
