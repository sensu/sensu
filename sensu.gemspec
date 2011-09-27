Gem::Specification.new do |s|
  s.name        = "sensu"
  s.version     = "0.6.1"
  s.authors     = ["Sean Porter", "Justin Kolberg"]
  s.email       = ["sean.porter@sonian.net", "justin.kolberg@sonian.net"]
  s.homepage    = "https://github.com/sonian/sensu"
  s.summary     = %q{A server monitoring framework}
  s.description = %q{A server monitoring framework using the publish-subscribe model}
  s.license     = "MIT"
  s.has_rdoc    = false

  s.platform = case ENV['BUILD']
  when "mingw"
    "x86-mingw32"
  when "mswin"
    "x86-mswin32"
  else
    RUBY_PLATFORM[/mingw32|mswin32/] || 'ruby'
  end

  s.add_dependency("eventmachine", "1.0.0.beta.4.1") if s.platform =~ /mswin|mingw32|windows/

  s.add_dependency("amqp", "0.7.4")
  s.add_dependency("json")
  s.add_dependency("uuidtools")
  s.add_dependency("em-syslog")

  unless s.platform =~ /mswin|mingw32|windows/
    s.add_dependency("em-hiredis")
    s.add_dependency("async_sinatra")
    s.add_dependency("thin")
  end

  s.add_development_dependency('rake')
  s.add_development_dependency('minitest')
  s.add_development_dependency('em-ventually')
  s.add_development_dependency('rest-client')

  s.files         = `git ls-files`.split("\n").reject {|f| f =~ /(dist|test)/}
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
