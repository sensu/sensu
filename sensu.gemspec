# -*- encoding: utf-8 -*-
require File.join(File.dirname(__FILE__), "lib", "sensu", "constants")

Gem::Specification.new do |s|
  s.name        = "sensu"
  s.version     = Sensu::VERSION
  s.authors     = ["Sean Porter", "Justin Kolberg"]
  s.email       = ["portertech@gmail.com", "amdprophet@gmail.com", "engineering@sensu.io"]
  s.homepage    = "https://sensu.io"
  s.summary     = "A monitoring framework"
  s.description = "A monitoring framework that aims to be simple, malleable, and scalable."
  s.license     = "MIT"

  s.add_dependency "eventmachine", "1.2.7"
  s.add_dependency "sensu-json", "2.1.1"
  s.add_dependency "sensu-logger", "1.2.2"
  s.add_dependency "sensu-settings", "10.17.0"
  s.add_dependency "sensu-extension", "1.5.2"
  s.add_dependency "sensu-extensions", "1.11.0"
  s.add_dependency "sensu-transport", "8.3.0"
  s.add_dependency "sensu-spawn", "2.5.0"
  s.add_dependency "sensu-redis", "2.4.0"
  s.add_dependency "em-http-server", "0.1.8"
  s.add_dependency "em-http-request", "1.1.5"
  s.add_dependency "parse-cron", "0.1.4"

  s.add_development_dependency "rake", "10.5.0"
  s.add_development_dependency "rspec", "~> 3.0.0"
  s.add_development_dependency "addressable", "2.3.8"
  s.add_development_dependency "webmock", "3.3.0"

  s.files         = Dir.glob("{exe,lib}/**/*") + %w[sensu.gemspec README.md CHANGELOG.md MIT-LICENSE.txt]
  s.executables   = s.files.grep(%r{^exe/}) { |file| File.basename(file) }
  s.bindir        = "exe"
  s.require_paths = ["lib"]
  s.cert_chain    = ['certs/sensu.pem']
  s.signing_key   = File.expand_path("~/.ssh/gem-sensu-private_key.pem") if $0 =~ /gem\z/
end
