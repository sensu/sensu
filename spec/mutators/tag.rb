#!/usr/bin/env ruby

require 'rubygems'
require 'multi_json'

event = Sensu::JSON.load(STDIN.read, :symbolize_keys => true)
event.merge!(:mutated => true)

puts Sensu::JSON.dump(event)
