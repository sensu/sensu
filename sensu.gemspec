# -*- encoding: utf-8 -*-
require File.join(File.dirname(__FILE__), 'lib', 'sensu', 'constants')

Gem::Specification.new do |s|
  s.name        = 'sensu'
  s.version     = Sensu::VERSION
  s.platform    = RUBY_PLATFORM =~ /java/ ? Gem::Platform::JAVA : Gem::Platform::RUBY
  s.authors     = ['Sean Porter', 'Justin Kolberg']
  s.email       = ['portertech@gmail.com', 'justin.kolberg@sonian.net']
  s.homepage    = 'https://github.com/sensu/sensu'
  s.summary     = 'A monitoring framework'
  s.description = 'A monitoring framework that aims to be simple, malleable, and scalable.'
  s.license     = 'MIT'
  s.has_rdoc    = false

  s.add_dependency('json') if RUBY_VERSION < "1.9"
  s.add_dependency('multi_json', '1.10.1')
  s.add_dependency('uuidtools', '2.1.4')
  s.add_dependency('sensu-em', '2.4.0')
  s.add_dependency('sensu-logger', '1.0.0')
  s.add_dependency('sensu-settings', '1.0.0')
  s.add_dependency('sensu-extension', '1.0.0')
  s.add_dependency('sensu-extensions', '1.0.0')
  s.add_dependency('sensu-transport', '1.0.0')
  s.add_dependency('sensu-spawn', '1.0.0')
  s.add_dependency('em-redis-unified', '0.5.0')
  s.add_dependency('sinatra', '1.3.5')
  s.add_dependency('async_sinatra', '1.0.0')
  s.add_dependency('thin', '1.5.0') unless RUBY_PLATFORM =~ /java/

  s.add_development_dependency('rake', '~> 10.3')
  s.add_development_dependency('rspec', '~> 3')
  s.add_development_dependency('em-http-request', '~> 1.1')

  s.files         = Dir.glob('{bin,lib}/**/*') + %w[sensu.gemspec README.md CHANGELOG.md MIT-LICENSE.txt]
  s.executables   = Dir.glob('bin/**/*').map { |file| File.basename(file) }
  s.require_paths = ['lib']
end
