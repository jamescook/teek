# Documentation tasks - all doc gems are in docs_site/Gemfile
namespace :docs do
  desc "Install docs dependencies (docs_site/Gemfile)"
  task :setup do
    Dir.chdir('docs_site') do
      Bundler.with_unbundled_env { sh 'bundle install' }
    end
  end

  task :yard_clean do
    FileUtils.rm_rf('doc')
    FileUtils.rm_rf('docs_site/_api')
    FileUtils.rm_rf('docs_site/_site')
    FileUtils.rm_rf('docs_site/.jekyll-cache')
    FileUtils.rm_f('docs_site/assets/js/search-data.json')
  end

  desc "Generate YARD JSON (uses docs_site/Gemfile)"
  task yard_json: :yard_clean do
    Bundler.with_unbundled_env do
      sh 'BUNDLE_GEMFILE=docs_site/Gemfile bundle exec yard doc'
    end
  end

  desc "Generate per-method coverage JSON from SimpleCov data"
  task :method_coverage do
    if Dir.exist?('coverage/results')
      require_relative '../teek/method_coverage_service'
      Teek::MethodCoverageService.new(coverage_dir: 'coverage').call
    else
      puts "No coverage data found (run tests with COVERAGE=1 first)"
    end
  end

  desc "Generate API docs (YARD JSON -> HTML)"
  task yard: [:yard_json, :method_coverage] do
    Bundler.with_unbundled_env do
      sh 'BUNDLE_GEMFILE=docs_site/Gemfile bundle exec ruby docs_site/build_api_docs.rb'
    end
  end

  desc "Bless recordings from recordings/ into docs_site/assets/recordings/"
  task :bless_recordings do
    require 'fileutils'
    src = 'recordings'
    dest = 'docs_site/assets/recordings'
    FileUtils.mkdir_p(dest)
    videos = Dir.glob("#{src}/*.{mp4,webm}")
    if videos.empty?
      puts "No recordings in #{src}/ to bless."
      next
    end
    videos.each do |path|
      FileUtils.cp(path, dest)
      puts "  #{File.basename(path)} -> #{dest}/"
    end
    puts "Blessed #{videos.size} recording(s)."
  end

  desc "Generate recordings gallery page"
  task :recordings do
    sh 'ruby docs_site/build_recordings.rb'
  end

  desc "Generate full docs site (YARD + Jekyll)"
  task generate: [:yard, :recordings] do
    Dir.chdir('docs_site') do
      Bundler.with_unbundled_env { sh 'bundle exec jekyll build' }
    end
    puts "Docs generated in docs_site/_site/"
  end

  desc "Serve docs locally"
  task serve: [:yard, :recordings] do
    Dir.chdir('docs_site') do
      Bundler.with_unbundled_env { sh 'bundle exec jekyll serve' }
    end
  end
end

# Aliases for convenience
task doc: 'docs:yard'
task yard: 'docs:yard'
