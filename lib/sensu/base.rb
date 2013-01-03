require 'rubygems'

gem 'eventmachine', '1.0.0'
gem 'amqp', '0.9.7'

require 'json'
require 'timeout'
require 'time'
require 'uri'
require 'amqp'

require File.join(File.dirname(__FILE__), 'constants')
require File.join(File.dirname(__FILE__), 'cli')
require File.join(File.dirname(__FILE__), 'logger')
require File.join(File.dirname(__FILE__), 'settings')
require File.join(File.dirname(__FILE__), 'extensions')
require File.join(File.dirname(__FILE__), 'process')
require File.join(File.dirname(__FILE__), 'io')

module Sensu
  class Base
    attr_reader :options, :settings, :extensions

    def initialize(options={})
      @options = Sensu::DEFAULT_OPTIONS.merge(options)
      setup_logging
      setup_settings
      setup_extensions
      setup_process
    end

    def setup_logging
      logger = Sensu::Logger.new
      logger.level = @options[:verbose] ? :debug : @options[:log_level] || :info
      logger.reopen(@options[:log_file])
      logger.setup_traps
    end

    def setup_settings
      @settings = Sensu::Settings.new
      @settings.load_env
      @settings.load_file(@options[:config_file])
      Dir[@options[:config_dir] + '/**/*.json'].each do |file|
        @settings.load_file(file)
      end
      @settings.validate
      @settings.set_env
    end

    def setup_extensions
      @extensions = Sensu::Extensions.new
      @extensions.load_all
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
