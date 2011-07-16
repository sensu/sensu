# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "sa-monitoring/version"

Gem::Specification.new do |s|
  s.name        = "sa-monitoring"
  s.version     = Sa::Monitoring::VERSION
  s.authors     = ["Sean Porter"]
  s.email       = ["portertech@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{TODO: Write a gem summary}
  s.description = %q{TODO: Write a gem description}

  s.rubyforge_project = "sa-monitoring"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
