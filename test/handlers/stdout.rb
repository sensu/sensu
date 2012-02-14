#!/usr/bin/env ruby

require 'rubygems'
require 'json'

event = JSON.parse(STDIN.read)

puts 'stdout -- test logging -- this should be first'
puts 'stdout -- test logging -- this should be second'

puts 'stdout -- ' + event.to_json
