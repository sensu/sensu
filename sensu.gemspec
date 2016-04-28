# -*- encoding: utf-8 -*-
require File.join(File.dirname(__FILE__), "lib", "sensu", "constants")

Gem::Specification.new do |s|
  s.name        = "sensu"
  s.version     = Sensu::VERSION
  s.platform    = RUBY_PLATFORM =~ /java/ ? Gem::Platform::JAVA : Gem::Platform::RUBY
  s.authors     = ["Sean Porter", "Justin Kolberg"]
  s.email       = ["portertech@gmail.com", "amdprophet@gmail.com"]
  s.homepage    = "http://sensuapp.org"
  s.summary     = "A monitoring framework"
  s.description = "A monitoring framework that aims to be simple, malleable, and scalable."
  s.license     = "MIT"
  s.has_rdoc    = false

  s.add_dependency "eventmachine", "1.2.0.1"
  s.add_dependency "sensu-json", "1.1.1"
  s.add_dependency "sensu-logger", "1.2.0"
  s.add_dependency "sensu-settings", "3.4.0"
  s.add_dependency "sensu-extension", "1.5.0"
  s.add_dependency "sensu-extensions", "1.5.0"
  s.add_dependency "sensu-transport", "6.0.0"
  s.add_dependency "sensu-spawn", "1.8.0"
  s.add_dependency "sensu-redis", "1.3.0"
  s.add_dependency "sinatra", "1.4.6"
  s.add_dependency "async_sinatra", "1.2.0"
  s.add_dependency "thin", "1.6.3" unless RUBY_PLATFORM =~ /java/

  s.add_development_dependency "rake", "10.5.0"
  s.add_development_dependency "rspec", "~> 3.0.0"
  s.add_development_dependency "em-http-request", "~> 1.1"
  s.add_development_dependency "addressable", "2.3.8"

  s.files         = Dir.glob("{exe,lib}/**/*") + %w[sensu.gemspec README.md CHANGELOG.md MIT-LICENSE.txt]
  s.executables   = s.files.grep(%r{^exe/}) { |file| File.basename(file) }
  s.bindir        = "exe"
  s.require_paths = ["lib"]
end
