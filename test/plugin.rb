#!/usr/bin/env ruby

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'optparse'

options = {}

optparse = OptionParser.new do |opts|
  opts.on('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end

  opts.on('-c', '--client NAME', 'Client NAME') do |client|
    options[:client] = client
  end

  opts.on('-e', '--exit CODE', 'Exit status CODE') do |code|
    options[:exit] = code.to_i
  end
end

optparse.parse!

unless options[:client] && options[:exit]
  puts "You must supply a client name (-c) and a exit status code (-e)"
  exit
end

sleep(2)

case options[:exit]
when 0
  puts "GOOD :: client '#{options[:client]}'"
  exit
when 1
  puts "WARNING :: client '#{options[:client]}'"
  exit 1
when 2
  puts "CRITICAL :: client '#{options[:client]}'"
  exit 2
when 3
  puts "UNKNOWN :: client '#{options[:client]}'"
  exit 3
end
