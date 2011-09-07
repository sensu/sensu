#!/usr/bin/env ruby

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'optparse'
require 'json'

options = {}

optparse = OptionParser.new do |opts|
  opts.on('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end

  opts.on('-f', '--file FILE', 'Event file') do |file|
    options[:file] = file
  end
end

optparse.parse!

unless options[:file]
  puts "You must supply an event file"
  exit
end

event = JSON.parse(File.open(options[:file], 'r').read)

if event.has_key?('action')
  puts event.to_json
end
