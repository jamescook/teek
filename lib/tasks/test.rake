Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/test_*.rb']
  t.verbose = true
end

task test: [:compile, :clean_coverage]

namespace :sdl2 do
  Rake::TestTask.new(:test) do |t|
    t.libs << 'teek-sdl2/test' << 'teek-sdl2/lib'
    t.test_files = FileList['teek-sdl2/test/**/test_*.rb'] - FileList['teek-sdl2/test/test_helper.rb']
    t.ruby_opts << '-r test_helper'
    t.verbose = true
  end
  task test: 'sdl2:compile'
end

namespace :ui do
  Rake::TestTask.new(:test) do |t|
    t.libs << 'teek-ui/test' << 'teek-ui/lib'
    t.test_files = FileList['teek-ui/test/**/test_*.rb'] - FileList['teek-ui/test/test_helper.rb']
    t.ruby_opts << '-r test_helper'
    t.verbose = true
  end
end
