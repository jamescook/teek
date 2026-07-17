desc 'Run clang-tidy on C code'
task :lint do
  # Find clang-tidy binary
  clang_tidy = nil

  # Try system PATH first (Linux, or if user has llvm in PATH)
  if system('which clang-tidy > /dev/null 2>&1')
    clang_tidy = 'clang-tidy'
  # On macOS, check Homebrew LLVM (keg-only, not in PATH by default)
  elsif system('which brew > /dev/null 2>&1')
    llvm_prefix = `brew --prefix llvm 2>/dev/null`.strip
    clang_tidy = "#{llvm_prefix}/bin/clang-tidy" if !llvm_prefix.empty? && File.exist?("#{llvm_prefix}/bin/clang-tidy")
  end

  unless clang_tidy
    abort("clang-tidy not installed.\n  " \
          "macOS: brew install llvm\n  " \
          "Ubuntu/Debian: apt-get install clang-tidy\n  " \
          'Fedora/RHEL: dnf install clang-tools-extra')
  end

  puts 'Running clang-tidy on C code...'

  # Find all .c files in ext/cataract/ and ext/cataract_color/
  c_files = Dir.glob('ext/teek/**/*.c') + Dir.glob('teek-sdl2/ext/**/*.c')

  # Run clang-tidy on each file
  # Note: clang-tidy uses the .clang-tidy config file automatically
  # We pass Ruby include path so it can find ruby.h
  ruby_include = RbConfig::CONFIG['rubyhdrdir']
  ruby_arch_include = RbConfig::CONFIG['rubyarchhdrdir']

  # Without an explicit -I, clang-tidy falls back to whatever tcl.h/tk.h it
  # finds on the default system search path - on macOS that's Apple's own
  # ancient bundled Tcl/Tk 8.5 (symlinked into the Command Line Tools SDK),
  # not the Homebrew tcl-tk this project actually builds against. That
  # header unconditionally needs X11/Xlib.h, which isn't in the SDK -
  # hence "file not found" even though the real build works fine.
  # pkg-config points at the same tcl-tk include dir extconf.rb uses,
  # which also bundles its own vendored X11 headers alongside tk.h, so no
  # separate X11 lookup is needed.
  tcltk_cflags = `pkg-config --cflags tcl tk 2>/dev/null`.strip.split
  if tcltk_cflags.empty?
    warn "Warning: pkg-config couldn't find tcl/tk - clang-tidy may pick up " \
         "the wrong (or no) tcl.h/tk.h. Install tcl-tk via Homebrew/apt, or " \
         "ensure pkg-config can see it."
  end

  # Same story for teek-sdl2: no explicit -I means clang-tidy won't find
  # SDL2/SDL.h (and friends) at all, since SDL2 has no system-bundled
  # fallback to silently misresolve to - it just fails outright.
  sdl2_cflags = `pkg-config --cflags sdl2 SDL2_ttf SDL2_image SDL2_mixer 2>/dev/null`.strip.split
  if sdl2_cflags.empty?
    warn "Warning: pkg-config couldn't find SDL2 - clang-tidy will fail on " \
         "teek-sdl2/ext/**/*.c. Install SDL2 (+ ttf/image/mixer) via " \
         "Homebrew/apt, or ensure pkg-config can see it."
  end

  success = c_files.all? do |file|
    puts "  Checking #{file}..."
    system(clang_tidy, '--quiet', file, '--',
           "-I#{ruby_include}",
           "-I#{ruby_arch_include}",
           '-Iext/teek',
           '-Iteek-sdl2/ext',
           *tcltk_cflags,
           *sdl2_cflags)
  end

  if success
    puts '✓ clang-tidy passed'
  else
    abort('clang-tidy found issues!')
  end
end
