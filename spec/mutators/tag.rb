#!/usr/bin/env ruby

require "rubygems"
require "sensu/json"

event = Sensu::JSON.load(STDIN.read)
event.merge!(:mutated => true)

puts Sensu::JSON.dump(event)
