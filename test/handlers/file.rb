#!/usr/bin/env ruby

require 'rubygems'
require 'json'

event = JSON.parse(STDIN.read, :symbolize_names => true)

File.open('/tmp/sensu_' + event[:check][:name], 'w') do |file|
  file.write(JSON.pretty_generate(event))
end
