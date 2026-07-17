namespace :release do
  desc "Clean-slate smoke test: clobber, build gems, install fresh, verify"
  task :smoke do
    require 'tmpdir'
    require 'fileutils'

    # Clean slate — nuke compiled extensions so nothing local leaks in
    puts "Clobbering local build artifacts..."
    Rake::Task['clobber'].invoke
    Rake::Task['sdl2:clobber'].invoke

    Dir.mktmpdir('teek-smoke') do |tmpdir|
      gem_home = File.join(tmpdir, 'gems')

      # Build both gems
      puts "\nBuilding gems..."
      sh "gem build teek.gemspec -o #{tmpdir}/teek.gem 2>&1"
      Dir.chdir('teek-sdl2') { sh "gem build teek-sdl2.gemspec -o #{tmpdir}/teek-sdl2.gem 2>&1" }

      # Install into isolated GEM_HOME (no system gems, no stale versions)
      puts "\nInstalling gems into #{gem_home}..."
      sh "GEM_HOME=#{gem_home} gem install #{tmpdir}/teek.gem --no-document 2>&1"
      sh "GEM_HOME=#{gem_home} gem install #{tmpdir}/teek-sdl2.gem --no-document 2>&1"

      # Run smoke test using only the installed gems (no -I, no bundle)
      puts "\nRunning smoke test..."
      smoke = <<~'RUBY'
        require "teek"
        require "teek/sdl2"

        # Verify native extensions loaded from gem path, not local source
        %w[tcltklib teek_sdl2].each do |ext|
          path = $LOADED_FEATURES.find { |f| f.include?(ext) && f.end_with?(".bundle", ".so", ".dll") }
          abort "#{ext}: native extension not found in $LOADED_FEATURES" unless path
          abort "#{ext}: loaded from local source (#{path}), not installed gem" if path.include?("/ext/")
        end

        app = Teek::App.new
        app.set_window_title("Release Smoke Test")
        app.set_window_geometry("320x240")
        app.show
        app.update

        vp = Teek::SDL2::Viewport.new(app, width: 300, height: 200)
        vp.pack
        app.update

        vp.render do |r|
          r.clear(30, 30, 30)
          r.fill(20, 20, 120, 80, r: 200, g: 50, b: 50)
          r.outline(160, 20, 120, 80, r: 50, g: 200, b: 50)
          r.line(20, 130, 280, 180, r: 50, g: 50, b: 200)
        end

        w, h = vp.renderer.output_size
        pixels = vp.renderer.read_pixels
        raise "read_pixels size mismatch" unless pixels.bytesize == w * h * 4

        app.after(500) { vp.destroy; app.destroy }
        app.mainloop
        puts "release:smoke OK — teek #{Teek::VERSION}, teek-sdl2 #{Teek::SDL2::VERSION}"
      RUBY

      smoke_file = File.join(tmpdir, 'smoke.rb')
      File.write(smoke_file, smoke)
      sh "GEM_HOME=#{gem_home} GEM_PATH=#{gem_home} ruby #{smoke_file}"
    end
  end
end
