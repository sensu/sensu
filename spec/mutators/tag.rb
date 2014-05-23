#!/usr/bin/env ruby

require 'rubygems'
require 'multi_json'

event = MultiJson.load(STDIN.read, :symbolize_keys => true)
event.merge!(:mutated => true)

puts MultiJson.dump(event)
