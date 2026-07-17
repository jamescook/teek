require "bundler/gem_tasks"
require 'rake/testtask'
require 'rake/clean'

# Sub-project Rakefiles (define sdl2:compile)
import 'teek-sdl2/Rakefile'

Dir.glob('lib/tasks/*.rake').sort.each { |f| load f }
