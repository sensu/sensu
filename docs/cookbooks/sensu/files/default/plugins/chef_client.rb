#!/usr/bin/env ruby

`which tasklist`

case
when $? == 0
  procs = `tasklist`
else
  procs = `ps aux`
end

running = false

procs.each_line do |proc|
  running = true if proc.include?('chef-client')
end

if running
  puts "CHEF CLIENT OK - Daemon is running"
  exit 0
else
  puts "CHEF CLIENT WARNING - Daemon is NOT running"
  exit 1
end
