require 'rubygems'

gem 'eventmachine', '~> 1.0.0.beta.4'

require 'optparse'
require 'time'
require 'json'
require 'hashie'
require 'cabin'
require 'amqp'

require File.join(File.dirname(__FILE__), 'constants')
require File.join(File.dirname(__FILE__), 'cli')
require File.join(File.dirname(__FILE__), 'logger')
require File.join(File.dirname(__FILE__), 'settings')

require File.join(File.dirname(__FILE__), 'patches', 'ruby')
require File.join(File.dirname(__FILE__), 'patches', 'amqp')

module Sensu
  class Config
    attr_reader :options, :logger, :settings

    def initialize(options={})
      @options = DEFAULT_OPTIONS.merge(options)
      @logger = Sensu::Logger.new(@options)
      setup_settings
    end

    def setup_settings
      settings = Sensu::Settings.new
      settings.load_env
      settings.load_file(@options[:config_file])
      Dir[@options[:config_dir] + '/**/*.json'].each do |file|
        settings.load_file(file)
      end
      begin
        settings.validate
      rescue => error
        @logger.fatal('CONFIG INVALID', {
          :error => error.to_s
        })
        @logger.fatal('SENSU NOT RUNNING!')
        exit 2
      end
      @settings = Hashie::Mash.new(settings.to_hash)
    end
  end
end
