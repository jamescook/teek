require_relative "lib/teek/ui/version"

Gem::Specification.new do |spec|
  spec.name          = "teek-ui"
  spec.version       = Teek::UI::VERSION
  spec.authors       = ["James Cook"]
  spec.email         = ["jcook.rubyist@gmail.com"]

  spec.summary       = "The friendly way to build Tk apps in Ruby"
  spec.description   = "Declarative widgets, layout, events, and reactive state on top of teek"
  spec.homepage      = "https://github.com/jamescook/teek"
  spec.licenses      = ["MIT"]

  spec.files         = Dir.glob("{lib,test}/**/*").select { |f|
                         File.file?(f) && f !~ /\.log$/
                       } + %w[teek-ui.gemspec CHANGELOG.md README.md]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.2"

  spec.add_dependency "teek", "~> 0.3"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 6.0"
end
