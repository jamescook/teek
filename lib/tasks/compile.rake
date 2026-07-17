# Compiling on macOS with Homebrew:
#
# Tcl/Tk 9.0:
#   rake clean && rake compile -- --with-tcltkversion=9.0 \
#     --with-tcl-lib=$(brew --prefix tcl-tk)/lib \
#     --with-tcl-include=$(brew --prefix tcl-tk)/include/tcl-tk \
#     --with-tk-lib=$(brew --prefix tcl-tk)/lib \
#     --with-tk-include=$(brew --prefix tcl-tk)/include/tcl-tk \
#     --without-X11
#
# Tcl/Tk 8.6:
#   rake clean && rake compile -- --with-tcltkversion=8.6 \
#     --with-tcl-lib=$(brew --prefix tcl-tk@8)/lib \
#     --with-tcl-include=$(brew --prefix tcl-tk@8)/include \
#     --with-tk-lib=$(brew --prefix tcl-tk@8)/lib \
#     --with-tk-include=$(brew --prefix tcl-tk@8)/include \
#     --without-X11

# Clean up extconf cached config files
CLEAN.include('ext/teek/config_list')
CLOBBER.include('tmp', 'lib/*.bundle', 'lib/*.so', 'ext/**/*.o', 'ext/**/*.bundle', 'ext/**/*.bundle.dSYM')
CLOBBER.include('teek-sdl2/lib/*.bundle', 'teek-sdl2/lib/*.so', 'teek-sdl2/ext/**/*.o', 'teek-sdl2/ext/**/*.bundle')

# rake compile = teek core only (tcltklib)
if Gem::Specification.find_all_by_name('rake-compiler').any?
  require 'rake/extensiontask'

  Rake::ExtensionTask.new do |ext|
    ext.name = 'tcltklib'
    ext.ext_dir = 'ext/teek'
    ext.lib_dir = 'lib'
  end
end

task :default => :compile
