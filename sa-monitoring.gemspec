# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "sa-monitoring/version"

Gem::Specification.new do |s|
  s.name        = "sa-monitoring"
  s.version     = SA::Monitoring::VERSION
  s.authors     = ["Sean Porter", "Justin Kolberg"]
  s.email       = ["sean.porter@sonian.net"]
  s.homepage    = "https://github.com/sonian/sa-monitoring"
  s.summary     = %q{Monitor servers}
  s.description = %q{Monitor servers}

  s.add_dependency('amqp', '0.7.1')
  s.add_dependency('json')
  s.add_dependency('uuidtools')
  s.add_dependency('em-hiredis')
  s.add_dependency('async_sinatra')

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
