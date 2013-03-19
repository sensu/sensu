# -*- encoding: utf-8 -*-
require File.join(File.dirname(__FILE__), 'lib', 'sensu', 'constants')

Gem::Specification.new do |s|
  s.name        = 'sensu'
  s.version     = Sensu::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Sean Porter', 'Justin Kolberg']
  s.email       = ['portertech@gmail.com', 'justin.kolberg@sonian.net']
  s.homepage    = 'https://github.com/sensu/sensu'
  s.summary     = 'A monitoring framework'
  s.description = 'A monitoring framework that aims to be simple, malleable, and scalable. Uses the publish/subscribe model.'
  s.license     = 'MIT'
  s.has_rdoc    = false

  s.add_dependency('oj', '2.0.9')
  s.add_dependency('eventmachine', '1.0.3')
  s.add_dependency('amqp', '0.9.10')
  s.add_dependency('em-redis-unified', '0.4.1')
  s.add_dependency('thin', '1.5.0')
  s.add_dependency('sinatra', '1.3.5')
  s.add_dependency('async_sinatra', '1.0.0')

  s.add_development_dependency('rake')
  s.add_development_dependency('rspec')
  s.add_development_dependency('em-http-request')

  s.files         = Dir.glob('{bin,lib}/**/*') + %w[sensu.gemspec README.md CHANGELOG.md MIT-LICENSE.txt]
  s.executables   = Dir.glob('bin/**/*').map { |file| File.basename(file) }
  s.require_paths = ['lib']
end
