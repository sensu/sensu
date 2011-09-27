#!/usr/bin/env ruby

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'json'

event = JSON.parse(STDIN.read)

puts 'name="Test Logging" event_id=handler:default reason="This should be first"'
puts 'name="Test Logging" event_id=handler:default reason="This should be second"'

File.open('/tmp/sensu_test_handlers', 'w') do |file|
  file.write(JSON.pretty_generate(event))
end
