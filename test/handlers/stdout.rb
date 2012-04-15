#!/usr/bin/env ruby

require 'rubygems'
require 'json'

event = JSON.parse(STDIN.read)

puts 'stdout -- handler logging test -- this should be first'
puts 'stdout -- handler logging test -- this should be second'

puts 'stdout -- ' + event.to_json
