#!/usr/bin/env ruby

require 'rubygems'
require 'json'

event = JSON.parse(STDIN.read)

puts 'test logging -- this should be first'
puts 'test logging -- this should be second'

File.open('/tmp/sensu_test_handlers', 'w') do |file|
  file.write(JSON.pretty_generate(event))
end
