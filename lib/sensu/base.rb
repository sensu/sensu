require 'rubygems'

gem 'oj', '2.0.9'
gem 'eventmachine', '1.0.3'

require 'time'
require 'uri'
require 'oj'

require File.join(File.dirname(__FILE__), 'constants')
require File.join(File.dirname(__FILE__), 'utilities')
require File.join(File.dirname(__FILE__), 'cli')
require File.join(File.dirname(__FILE__), 'logstream')
require File.join(File.dirname(__FILE__), 'settings')
require File.join(File.dirname(__FILE__), 'extensions')
require File.join(File.dirname(__FILE__), 'process')
require File.join(File.dirname(__FILE__), 'io')
require File.join(File.dirname(__FILE__), 'rabbitmq')

Oj.default_options = {:mode => :compat, :symbol_keys => true}

module Sensu
  class Base
    def initialize(options={})
      @options = options
    end

    def logger
      logger = Logger.get
      if @options[:log_level]
        logger.level = @options[:log_level]
      end
      if @options[:log_file]
        logger.reopen(@options[:log_file])
      end
      logger.setup_traps
      logger
    end

    def settings
      settings = Settings.new
      settings.load_env
      if @options[:config_file]
        settings.load_file(@options[:config_file])
      end
      if @options[:config_dir]
        settings.load_directory(@options[:config_dir])
      end
      settings.validate
      settings.set_env
      settings
    end

    def extensions
      extensions = Extensions.new
      if @options[:extension_dir]
        extensions.require_directory(@options[:extension_dir])
      end
      extensions.load_all
      extensions
    end

    def setup_process
      process = Process.new
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
