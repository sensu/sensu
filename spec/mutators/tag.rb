#!/usr/bin/env ruby

require 'rubygems'
require 'oj'

event = Oj.load(STDIN.read)
event.merge!(:mutated => true)

puts Oj.dump(event)
