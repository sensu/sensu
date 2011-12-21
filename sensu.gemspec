require File.expand_path("../lib/sensu", __FILE__)

Gem::Specification.new do |s|
  s.name        = "sensu"
#  s.version     = Sensu::VERSION + ".copia1"
  s.version     = Sensu::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Sean Porter", "Justin Kolberg"]
  s.email       = ["sean.porter@sonian.net", "justin.kolberg@sonian.net"]
  s.homepage    = "https://github.com/sonian/sensu"
  s.summary     = "A monitoring framework"
  s.description = "A monitoring framework that aims to be simple, malleable, and scalable. Uses the publish/subscribe model."
  s.license     = "MIT"
  s.has_rdoc    = false

  s.add_dependency("bundler")
  s.add_dependency("eventmachine", "~> 1.0.0.beta.4")
  s.add_dependency("amqp", "0.7.4")
  s.add_dependency("json")
  s.add_dependency("hashie")
  s.add_dependency("cabin", "0.1.7")
  s.add_dependency("ruby-redis")
  s.add_dependency("rack", "~> 1.3.4")
  s.add_dependency("async_sinatra")
  s.add_dependency("thin")

  s.add_development_dependency("rake")
  s.add_development_dependency("em-spec")
  s.add_development_dependency("em-http-request")

  s.files         = `git ls-files`.split("\n").reject {|f| f =~ /(dist|test|png)/}
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
