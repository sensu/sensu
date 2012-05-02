require 'rubygems'

gem 'eventmachine', '~> 1.0.0.beta.4'

require 'optparse'
require 'json'
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
  class Config
    attr_reader :options, :logger, :settings

    def initialize(options={})
      @options = DEFAULT_OPTIONS.merge(options)
      @logger = Cabin::Channel.get
      setup_logging
      setup_settings
      setup_process
    end

    def setup_logging
      Sensu::Logger.new(@options)
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
        @logger.fatal('CONFIG INVALID', {
          :error => error.to_s
        })
        @logger.fatal('SENSU NOT RUNNING!')
        exit 2
      end
    end

    def setup_process
      Sensu::Process.new(@options)
    end
  end
end
