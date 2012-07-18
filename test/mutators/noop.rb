#!/usr/bin/env ruby

require 'rubygems'
require 'json'

event = JSON.parse(STDIN.read)

puts event.to_json
