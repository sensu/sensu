Gem::Specification.new do |s|
  s.name        = "sensu"
  s.version     = "0.5.6"
  s.authors     = ["Sean Porter", "Justin Kolberg"]
  s.email       = ["sean.porter@sonian.net", "justin.kolberg@sonian.net"]
  s.homepage    = "https://github.com/sonian/sensu"
  s.summary     = %q{A server monitoring framework}
  s.description = %q{A server monitoring framework using the publish-subscribe model}
  s.license     = "MIT"
  s.has_rdoc    = false

  s.add_dependency("amqp", "0.7.4")
  s.add_dependency("json")
  s.add_dependency("uuidtools")
  s.add_dependency("em-hiredis")
  s.add_dependency("em-syslog")
  s.add_dependency("async_sinatra")
  s.add_dependency("thin")
  s.add_development_dependency('rake')
  s.add_development_dependency('minitest')
  s.add_development_dependency('em-ventually')
  s.add_development_dependency('rest-client')

  s.files         = `git ls-files`.split("\n").reject {|f| f =~ /(dist|test)/}
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
