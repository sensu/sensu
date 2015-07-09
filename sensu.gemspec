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

  s.add_dependency "json" if RUBY_VERSION < "1.9"
  s.add_dependency "multi_json", "1.11.2"
  s.add_dependency "uuidtools", "2.1.5"
  s.add_dependency "eventmachine", "1.0.3"
  s.add_dependency "sensu-em", "2.5.2"
  s.add_dependency "sensu-logger", "1.0.0"
  s.add_dependency "sensu-settings", "3.0.0"
  s.add_dependency "sensu-extension", "1.1.2"
  s.add_dependency "sensu-extensions", "1.2.0"
  s.add_dependency "sensu-transport", "3.0.0"
  s.add_dependency "sensu-spawn", "1.3.0"
  s.add_dependency "em-redis-unified", "1.0.0"
  s.add_dependency "sinatra", "1.4.6"
  s.add_dependency "async_sinatra", "1.2.0"
  s.add_dependency "thin", "1.6.3" unless RUBY_PLATFORM =~ /java/

  s.add_development_dependency "rake", "~> 10.3"
  s.add_development_dependency "rspec", "~> 3.0.0"
  s.add_development_dependency "em-http-request", "~> 1.1"

  s.files         = Dir.glob("{bin,lib}/**/*") + %w[sensu.gemspec README.md CHANGELOG.md MIT-LICENSE.txt]
  s.executables   = Dir.glob("bin/**/*").map { |file| File.basename(file) }
  s.require_paths = ["lib"]
end
