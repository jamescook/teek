# Docker tasks for local testing and CI
namespace :docker do
  DOCKERFILE = 'Dockerfile.ci-test'
  DOCKER_LABEL = 'project=teek'

  def docker_image_name(tcl_version, ruby_version = nil)
    ruby_version ||= ruby_version_from_env
    base = tcl_version == '8.6' ? 'teek-ci-test-8' : 'teek-ci-test-9'
    ruby_version == '4.0' ? base : "#{base}-ruby#{ruby_version}"
  end

  def warn_if_containers_running(image_name)
    running = `docker ps --filter ancestor=#{image_name} --format '{{.ID}} {{.Status}}'`.strip
    return if running.empty?
    count = running.lines.size
    warn "\n⚠  #{count} container(s) already running on #{image_name}:"
    running.lines.each { |l| warn "   #{l.strip}" }
    warn "   This usually means a previous test suite is stuck. Consider: docker kill $(docker ps -q --filter ancestor=#{image_name})\n"
  end

  def tcl_version_from_env
    version = ENV.fetch('TCL_VERSION', '9.0')
    unless ['8.6', '9.0'].include?(version)
      abort "Invalid TCL_VERSION='#{version}'. Must be '8.6' or '9.0'."
    end
    version
  end

  def ruby_version_from_env
    ENV.fetch('RUBY_VERSION', '4.0')
  end

  desc "Build Docker image (TCL_VERSION=9.0|8.6, RUBY_VERSION=3.4|4.0|...)"
  task :build do
    tcl_version = tcl_version_from_env
    ruby_version = ruby_version_from_env
    image_name = docker_image_name(tcl_version, ruby_version)

    verbose = ENV['VERBOSE'] || ENV['V']
    quiet = !verbose
    if quiet
      puts "Building Docker image for Ruby #{ruby_version}, Tcl #{tcl_version}... (VERBOSE=1 for details)"
    else
      puts "Building Docker image for Ruby #{ruby_version}, Tcl #{tcl_version}..."
    end
    cmd = "docker build -f #{DOCKERFILE}"
    cmd += " -q" if quiet
    cmd += " --label #{DOCKER_LABEL}"
    cmd += " --build-arg RUBY_VERSION=#{ruby_version}"
    cmd += " --build-arg TCL_VERSION=#{tcl_version}"
    cmd += " -t #{image_name} ."

    sh cmd, verbose: !quiet
  end

  desc "Run tests in Docker (TCL_VERSION=9.0|8.6, RUBY_VERSION=3.4|4.0|..., TEST=path/to/test.rb)"
  task test: :build do
    tcl_version = tcl_version_from_env
    ruby_version = ruby_version_from_env
    image_name = docker_image_name(tcl_version, ruby_version)

    require 'fileutils'
    FileUtils.mkdir_p('coverage')

    warn_if_containers_running(image_name)

    puts "Running tests in Docker (Ruby #{ruby_version}, Tcl #{tcl_version})..."
    cmd = "docker run --rm --init"
    cmd += " -v #{Dir.pwd}/coverage:/app/coverage"
    cmd += " -e TCL_VERSION=#{tcl_version}"
    cmd += " -e TEST='#{ENV['TEST']}'" if ENV['TEST']
    cmd += " -e TESTOPTS='#{ENV['TESTOPTS']}'" if ENV['TESTOPTS']
    if ENV['COVERAGE'] == '1'
      cmd += " -e COVERAGE=1"
      cmd += " -e COVERAGE_NAME=#{ENV['COVERAGE_NAME'] || 'main'}"
    end
    cmd += " #{image_name}"

    sh cmd
  end

  desc "Run interactive shell in Docker (TCL_VERSION=9.0|8.6, RUBY_VERSION=3.4|4.0|...)"
  task shell: :build do
    tcl_version = tcl_version_from_env
    ruby_version = ruby_version_from_env
    image_name = docker_image_name(tcl_version, ruby_version)

    cmd = "docker run --rm --init -it"
    cmd += " -v #{Dir.pwd}/coverage:/app/coverage"
    cmd += " -e TCL_VERSION=#{tcl_version}"
    cmd += " #{image_name} bash"

    sh cmd
  end

  desc "Force rebuild Docker image (no cache)"
  task :rebuild do
    tcl_version = tcl_version_from_env
    ruby_version = ruby_version_from_env
    image_name = docker_image_name(tcl_version, ruby_version)

    puts "Rebuilding Docker image (no cache) for Ruby #{ruby_version}, Tcl #{tcl_version}..."
    cmd = "docker build -f #{DOCKERFILE} --no-cache"
    cmd += " --label #{DOCKER_LABEL}"
    cmd += " --build-arg RUBY_VERSION=#{ruby_version}"
    cmd += " --build-arg TCL_VERSION=#{tcl_version}"
    cmd += " -t #{image_name} ."

    sh cmd
  end

  desc "Remove dangling Docker images from teek builds"
  task :prune do
    sh "docker image prune -f --filter label=#{DOCKER_LABEL}"
  end

  Rake::Task['docker:test'].enhance { Rake::Task['docker:prune'].invoke }

  namespace :test do
    desc "Run teek-sdl2 tests in Docker"
    task sdl2: :build do
      tcl_version = tcl_version_from_env
      ruby_version = ruby_version_from_env
      image_name = docker_image_name(tcl_version, ruby_version)

      require 'fileutils'
      FileUtils.mkdir_p('coverage')

      warn_if_containers_running(image_name)

      puts "Running teek-sdl2 tests in Docker (Ruby #{ruby_version}, Tcl #{tcl_version})..."
      cmd = "docker run --rm --init"
      cmd += " -v #{Dir.pwd}/coverage:/app/coverage"
      cmd += " -v #{Dir.pwd}/screenshots:/app/screenshots"
      cmd += " -e TCL_VERSION=#{tcl_version}"
      if ENV['COVERAGE'] == '1'
        cmd += " -e COVERAGE=1"
        cmd += " -e COVERAGE_NAME=#{ENV['COVERAGE_NAME'] || 'sdl2'}"
      end
      cmd += " #{image_name}"
      cmd += " xvfb-run -a bundle exec rake sdl2:test"

      sh cmd
    end

    desc "Run teek-ui tests in Docker"
    task ui: :build do
      tcl_version = tcl_version_from_env
      ruby_version = ruby_version_from_env
      image_name = docker_image_name(tcl_version, ruby_version)

      require 'fileutils'
      FileUtils.mkdir_p('coverage')

      warn_if_containers_running(image_name)

      puts "Running teek-ui tests in Docker (Ruby #{ruby_version}, Tcl #{tcl_version})..."
      cmd = "docker run --rm --init"
      cmd += " -v #{Dir.pwd}/coverage:/app/coverage"
      cmd += " -e TCL_VERSION=#{tcl_version}"
      if ENV['COVERAGE'] == '1'
        cmd += " -e COVERAGE=1"
        cmd += " -e COVERAGE_NAME=#{ENV['COVERAGE_NAME'] || 'ui'}"
      end
      cmd += " #{image_name}"
      cmd += " xvfb-run -a bundle exec rake ui:test"

      sh cmd
    end

    desc "Run all tests (teek + teek-sdl2) with coverage and generate report"
    task all: 'docker:build' do
      tcl_version = tcl_version_from_env
      ruby_version = ruby_version_from_env
      image_name = docker_image_name(tcl_version, ruby_version)

      require 'fileutils'
      FileUtils.rm_rf('coverage')
      FileUtils.mkdir_p('coverage/results')

      # Run all test suites with coverage enabled and distinct COVERAGE_NAMEs
      ENV['COVERAGE'] = '1'

      ENV['COVERAGE_NAME'] = 'main'
      Rake::Task['docker:test'].invoke

      ENV['COVERAGE_NAME'] = 'sdl2'
      Rake::Task['docker:test:sdl2'].reenable
      Rake::Task['docker:build'].reenable
      Rake::Task['docker:test:sdl2'].invoke

      ENV['COVERAGE_NAME'] = 'ui'
      Rake::Task['docker:test:ui'].reenable
      Rake::Task['docker:build'].reenable
      Rake::Task['docker:test:ui'].invoke

      # Collate inside Docker (paths match /app/lib/...)
      puts "Collating coverage results..."
      cmd = "docker run --rm --init"
      cmd += " -v #{Dir.pwd}/coverage:/app/coverage"
      cmd += " #{image_name}"
      cmd += " bundle exec rake coverage:collate"

      sh cmd

      # Generate per-method coverage (runs locally, just needs Prism)
      puts "Generating per-method coverage..."
      Rake::Task['docs:method_coverage'].invoke

      puts "Coverage report: coverage/index.html"
    end
  end

  namespace :screenshots do
    desc "Bless linux screenshots inside Docker (copies unverified/ to blessed/)"
    task bless: :build do
      ruby_version = ruby_version_from_env
      tcl_version = tcl_version_from_env
      image_name = docker_image_name(tcl_version, ruby_version)

      cmd = "docker run --rm --init"
      cmd += " -v #{Dir.pwd}/screenshots:/app/screenshots"
      cmd += " #{image_name}"
      cmd += " bundle exec rake screenshots:bless"

      sh cmd
    end
  end

  # Scan sample files for # teek-record magic comment
  # Format: # teek-record: title=My Demo, codec=vp9
  def find_recordable_samples
    Dir['sample/**/*.rb', 'teek-sdl2/sample/**/*.rb'].filter_map do |path|
      first_lines = File.read(path, 500)
      match = first_lines.match(/^#\s*teek-record(?::\s*(.+))?$/)
      next unless match

      options = {}
      if match[1]
        match[1].split(',').each do |pair|
          key, value = pair.strip.split('=', 2)
          options[key.strip] = value&.strip if key
        end
      end
      options['sample'] = path
      options
    end
  end

  desc "Record demos in Docker (TCL_VERSION=9.0|8.6, DEMO=sample/foo.rb)"
  task record_demos: :build do
    require 'fileutils'
    FileUtils.mkdir_p('recordings')

    demos = if ENV['DEMO']
              find_recordable_samples.select { |d| d['sample'] == ENV['DEMO'] }
            else
              find_recordable_samples
            end

    if demos.empty?
      puts "No recordable samples found. Add '# teek-record' comment to samples."
      next
    end

    demos.each do |demo|
      sample = demo['sample']
      codec = ENV['CODEC'] || demo['codec'] || 'x264'
      name = demo['name']

      puts
      puts "Recording #{sample} (#{codec})..."
      env = "CODEC=#{codec}"
      env += " NAME=#{name}" if name
      env += " AUDIO=1" if demo['audio']
      sh "#{env} ./scripts/docker-record.sh #{sample}"
    end

    puts "Done! Recordings in: recordings/"
  end

  Rake::Task['docker:record_demos'].enhance { Rake::Task['docker:prune'].invoke }
end
