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
end

optparse.parse!

unless options[:client]
  puts "You must supply a client name"
  exit
end

time = (0..30).to_a.sample

case (0..3).to_a.sample
when 0
  sleep(time)
  puts "GOOD :: sleep => #{time} :: client => #{options[:client]}"
  exit
when 1
  sleep(time)
  puts "WARNING :: sleep => #{time} :: client => #{options[:client]}"
  exit 1
when 2
  sleep(time)
  puts "CRITICAL :: sleep => #{time} :: client => #{options[:client]}"
  exit 2
when 3
  sleep(time)
  puts "UNKNOWN :: sleep => #{time} :: client => #{options[:client]}"
  exit 3
end
