require 'rubygems'

gem 'eventmachine', '1.0.0'

require 'json'
require 'time'
require 'uri'

require File.join(File.dirname(__FILE__), 'constants')
require File.join(File.dirname(__FILE__), 'utilities')
require File.join(File.dirname(__FILE__), 'cli')
require File.join(File.dirname(__FILE__), 'logstream')
require File.join(File.dirname(__FILE__), 'settings')
require File.join(File.dirname(__FILE__), 'extensions')
require File.join(File.dirname(__FILE__), 'process')
require File.join(File.dirname(__FILE__), 'io')
require File.join(File.dirname(__FILE__), 'rabbitmq')

module Sensu
  class Base
    def initialize(options={})
      @options = DEFAULT_OPTIONS.merge(options)
    end

    def logger
      stream = LogStream.new
      stream.level = @options[:log_level]
      if @options[:log_file]
        stream.reopen(@options[:log_file])
      end
      stream.setup_traps
      stream.logger
    end

    def settings
      settings = Settings.new
      settings.load_env
      settings.load_file(@options[:config_file])
      settings.load_directory(@options[:config_dir])
      settings.validate
      settings.set_env
      settings
    end

    def extensions
      extensions = Extensions.new(settings)
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
