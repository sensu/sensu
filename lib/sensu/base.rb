require 'rubygems'

gem 'eventmachine', '~> 1.0.0.beta.4'

require 'optparse'
require 'json'
require 'time'
require 'uri'
require 'cabin'
require 'amqp'

require File.join(File.dirname(__FILE__), 'patches', 'ruby')
require File.join(File.dirname(__FILE__), 'patches', 'amqp')

require File.join(File.dirname(__FILE__), 'constants')
require File.join(File.dirname(__FILE__), 'cli')
require File.join(File.dirname(__FILE__), 'logger')
require File.join(File.dirname(__FILE__), 'settings')
require File.join(File.dirname(__FILE__), 'process')

module Sensu
  class Base
    attr_reader :options, :logger, :settings

    def initialize(options={})
      @options = Sensu::DEFAULT_OPTIONS.merge(options)
      @logger = Cabin::Channel.get
      setup_logging
      setup_settings
      setup_process
    end

    def setup_logging
      logger = Sensu::Logger.new(@options)
      logger.reopen
      logger.setup_traps
    end

    def setup_settings
      @settings = Sensu::Settings.new
      @settings.load_env
      @settings.load_file(@options[:config_file])
      Dir[@options[:config_dir] + '/**/*.json'].each do |file|
        @settings.load_file(file)
      end
      begin
        @settings.validate
      rescue => error
        @logger.fatal('config invalid', {
          :error => error.to_s
        })
        @logger.fatal('SENSU NOT RUNNING!')
        exit 2
      end
      @settings.set_env
    end

    def setup_process
      process = Sensu::Process.new
      if @options[:daemonize]
        process.daemonize
      end
      if @options[:pid_file]
        process.write_pid(@options[:pid_file])
      end
      process.setup_eventmachine
    end
  end
end
