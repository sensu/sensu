#!/usr/bin/env ruby

require 'rubygems'
require 'json'

event = JSON.parse(STDIN.read, :symbolize_names => true)
event.merge!(:mutated => true)

puts event.to_json
