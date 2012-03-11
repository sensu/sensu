#!/usr/bin/env ruby
#
# Check Procs
# ===
#
# Finds processes matching various filters (name, state, etc). Will not
# match itself by default. The number of processes found will be tested
# against the Warning/critical thresholds. By default, fails with a
# CRITICAL if more than one process matches -- you must specify values
# for -w and -c to override this.
#
# Attempts to work on Cygwin (where ps does not have the features we
# need) by calling Windows' tasklist.exe, but this is not well tested.
#
# Examples:
#
#   # chef-client is running
#   check-procs -p chef-client -W 1
#
#   # there are not too many zombies
#   check-procs -s Z -w 5 -c 10
#
# Copyright 2011 Sonian, Inc.
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'

class CheckProcs < Sensu::Plugin::Check::CLI

  option :warn_over, :short => '-w N', :proc => proc {|a| a.to_i }, :default => 1
  option :crit_over, :short => '-c N', :proc => proc {|a| a.to_i }, :default => 1
  option :warn_under, :short => '-W N', :proc => proc {|a| a.to_i }, :default => 0
  option :crit_under, :short => '-C N', :proc => proc {|a| a.to_i }, :default => 0
  option :metric, :short => '-t METRIC', :proc => proc {|a| a.to_sym }

  option :match_self, :short => '-m', :boolean => true, :default => false
  option :match_parent, :short => '-M', :boolean => true, :default => false
  option :cmd_pat, :short => '-p PATTERN'
  option :file_pid, :short => '-f PATH', :proc => proc {|a| File.read(a).chomp.to_i }
  option :vsz, :short => '-z VSZ', :proc => proc {|a| a.to_i }
  option :rss, :short => '-r RSS', :proc => proc {|a| a.to_i }
  option :pcpu, :short => '-P PCPU', :proc => proc {|a| a.to_f }
  option :state, :short => '-s STATE', :proc => proc {|a| a.split(',') }
  option :user, :short => '-u USER', :proc => proc {|a| a.split(',') }

  def read_lines(cmd)
    IO.popen(cmd + ' 2>&1') do |child|
      child.read.split("\n")
    end
  end

  def line_to_hash(line, *cols)
    Hash[cols.zip(line.strip.split(/\s+/, cols.size))]
  end

  def on_cygwin?
    `ps -W 2>&1`; $?.exitstatus == 0
  end

  def get_procs
    if on_cygwin?
      read_lines('ps -aWl').drop(1).map do |line|
        # Horrible hack because cygwin's ps has no o option, every
        # format includes the STIME column (which may contain spaces),
        # and the process state (which isn't actually a column) can be
        # blank. As of revision 1.35, the format is:
        # const char *lfmt = "%c %7d %7d %7d %10u %4s %4u %8s %s\n";
        state = line.slice!(0..0)
        stime = line.slice!(45..53)
        line_to_hash(line, :pid, :ppid, :pgid, :winpid, :tty, :uid, :command).merge(:state => state)
      end
    else
      read_lines('ps axwwo user,pid,vsz,rss,pcpu,state,command').drop(1).map do |line|
        line_to_hash(line, :user, :pid, :vsz, :rss, :pcpu, :state, :command)
      end
    end
  end

  def run
    procs = get_procs

    procs.reject! {|p| p[:pid].to_i != config[:file_pid] } if config[:file_pid]
    procs.reject! {|p| p[:pid].to_i == $$ } unless config[:match_self]
    procs.reject! {|p| p[:pid].to_i == Process.ppid } unless config[:match_parent]
    procs.reject! {|p| p[:command] !~ /#{config[:cmd_pat]}/ } if config[:cmd_pat]
    procs.reject! {|p| p[:vsz].to_f < config[:vsz] } if config[:vsz]
    procs.reject! {|p| p[:rss].to_f < config[:rss] } if config[:rss]
    procs.reject! {|p| p[:pcpu].to_f < config[:pcpu] } if config[:pcpu]
    procs.reject! {|p| !config[:state].include?(p[:state]) } if config[:state]
    procs.reject! {|p| !config[:user].include?(p[:user]) } if config[:user]

    msg = "Found #{procs.size} matching processes"
    msg += "; cmd /#{config[:cmd_pat]}/" if config[:cmd_pat]
    msg += "; state #{config[:state].join(',')}" if config[:state]
    msg += "; user #{config[:user].join(',')}" if config[:user]
    msg += "; rss > #{config[:vsz]}" if config[:vsz]
    msg += "; vsz > #{config[:rss]}" if config[:rss]
    msg += "; pcpu > #{config[:pcpu]}" if config[:pcpu]
    msg += "; pid #{config[:file_pid]}" if config[:file_pid]

    count = if config[:metric]
      procs.map {|p| p[config[:metric]].to_i }.reduce {|a, b| a + b }
    else
      procs.size
    end

    if count < config[:crit_under] || count > config[:crit_over]
      critical msg
    elsif count < config[:warn_under] || count > config[:warn_over]
      warning msg
    else
      ok msg
    end
  end

end
