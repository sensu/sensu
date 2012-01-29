#!/usr/bin/env ruby
# Copyright 2011 James Turnbull
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Puppet Master Plugin
# ===
#
# This plugin checks to see if the Puppet Labs Puppet master is running
#

`which tasklist`
case
when $? == 0
  procs = `tasklist`
else
  procs = `ps aux`
end
running = false
procs.each_line do |proc|
  running = true if proc.find { |p| /puppetmasterd|puppet master/ =~ p }
end
if running
  puts 'PUPPET Master - OK - Puppet master is running'
  exit 0
else
  puts 'PUPPET Master - WARNING - Puppet master is NOT running'
  exit 1
end
