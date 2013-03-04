#!/usr/bin/env ruby

require 'rubygems'
require 'oj'

Oj.default_options = {:mode => :compat, :symbol_keys => true}

event = Oj.load(STDIN.read)
event.merge!(:mutated => true)

puts Oj.dump(event)
