Gem::Specification.new do |s|
  s.name        = "sa-monitoring"
  s.version     = "0.0.8"
  s.authors     = ["Sean Porter", "Justin Kolberg"]
  s.email       = ["sean.porter@sonian.net", "justin.kolberg@sonian.net"]
  s.homepage    = "https://github.com/sonian/sa-monitoring"
  s.summary     = %q{Pub/Sub Server Monitoring}
  s.description = %q{Monitor servers with Ruby EventMachine & RabbitMQ}

  s.add_dependency("amqp", "0.7.4")
  s.add_dependency("json")
  s.add_dependency("uuidtools")
  s.add_dependency("em-hiredis")
  s.add_dependency("async_sinatra")

  s.files         = `git ls-files`.split("\n").reject {|f| f =~ /dist/}
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
