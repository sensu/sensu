# -*- encoding: utf-8 -*-
require File.join(File.dirname(__FILE__), "lib", "sensu", "constants")

Gem::Specification.new do |s|
  s.name        = "sensu"
  s.version     = Sensu::VERSION
  s.authors     = ["Sean Porter", "Justin Kolberg"]
  s.email       = ["portertech@gmail.com", "amdprophet@gmail.com"]
  s.homepage    = "http://sensuapp.org"
  s.summary     = "A monitoring framework"
  s.description = "A monitoring framework that aims to be simple, malleable, and scalable."
  s.license     = "MIT"
  s.has_rdoc    = false

  s.add_dependency "eventmachine", "1.2.5"
  s.add_dependency "sensu-json", "2.1.0"
  s.add_dependency "sensu-logger", "1.2.1"
  s.add_dependency "sensu-settings", "10.10.0"
  s.add_dependency "sensu-extension", "1.5.1"
  s.add_dependency "sensu-extensions", "1.9.0"
  s.add_dependency "sensu-transport", "7.0.2"
  s.add_dependency "sensu-spawn", "2.2.1"
  s.add_dependency "sensu-redis", "2.2.0"
  s.add_dependency "em-http-server", "0.1.8"
  s.add_dependency "parse-cron", "0.1.4"

  s.add_development_dependency "rake", "10.5.0"
  s.add_development_dependency "rspec", "~> 3.0.0"
  s.add_development_dependency "em-http-request", "~> 1.1"
  s.add_development_dependency "addressable", "2.3.8"

  s.files         = Dir.glob("{exe,lib}/**/*") + %w[sensu.gemspec README.md CHANGELOG.md MIT-LICENSE.txt]
  s.executables   = s.files.grep(%r{^exe/}) { |file| File.basename(file) }
  s.bindir        = "exe"
  s.require_paths = ["lib"]
end
