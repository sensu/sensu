require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'bundler/setup'

require File.join(File.dirname(__FILE__), 'helpers')

gem 'eventmachine', '~> 1.0.0.beta.4'

require 'optparse'
require 'json'
require 'hashie'
require 'uuidtools'
require 'amqp'
require 'cabin'
require 'cabin/outputs/em-stdlib-logger'

module Sensu
  class Config
    attr_accessor :settings, :logger

    def initialize(options={})
      @logger = Cabin::Channel.new
      log_file = options[:log_file] || '/tmp/sensu.log'
      if File.writable?(log_file) || !File.exist?(log_file) && File.writable?(File.dirname(log_file))
        ruby_logger = Logger.new(log_file)
      else
        invalid_config('log file is not writable: ' + log_file)
      end
      @logger.subscribe(Cabin::Outputs::EmStdlibLogger.new(ruby_logger))
      @logger.level = options[:verbose] ? :debug : :info
      config_file = options[:config_file] || '/etc/sensu/config.json'
      if File.readable?(config_file)
        begin
          @settings = Hashie::Mash.new(JSON.parse(File.open(config_file, 'r').read))
        rescue JSON::ParserError => e
          invalid_config('configuration file must be valid JSON: ' + e)
        end
      else
        invalid_config('configuration file does not exist or is not readable: ' + config_file)
      end
      validate_config(options['type'])
    end

    def toggle_log_level
      @logger.level = @logger.level == :info ? :debug : :info
    end

    def validate_config(type)
      @logger.debug('[config] -- validating configuration')
      has_keys(%w[rabbitmq])
      case type
      when 'server'
        has_keys(%w[redis handlers checks])
        unless @settings.handlers.include?('default')
          invalid_config('missing default handler')
        end
      when 'api'
        has_keys(%w[redis api])
      when 'client'
        has_keys(%w[client checks])
        unless @settings.client.name.is_a?(String)
          invalid_config('client must have a name')
        end
        unless @settings.client.address.is_a?(String)
          invalid_config('client must have an address (ip or hostname)')
        end
        unless @settings.client.subscriptions.is_a?(Array) && @settings.client.subscriptions.count > 0
          invalid_config('client must have subscriptions')
        end
      end
      @settings.checks.each do |name, details|
        unless details.interval.is_a?(Integer) && details.interval > 0
          invalid_config('missing interval for check ' + name)
        end
        unless details.command.is_a?(String)
          invalid_config('missing command for check ' + name)
        end
        unless details.subscribers.is_a?(Array) && details.subscribers.count > 0
          invalid_config('missing subscribers for check ' + name)
        end
        if details.key?('handler')
          unless details.handler.is_a?(String)
            invalid_config('handler must be a string for check ' + name)
          end
        end
        if details.key?('handlers')
          unless details.handlers.is_a?(Array)
            invalid_config('handlers must be an array for check ' + name)
          end
        end
      end
      if type
        @logger.debug('[config] -- configuration valid -- running ' + type)
        puts 'configuration valid -- running ' + type
      end
    end

    def has_keys(keys)
      keys.each do |key|
        unless @settings.key?(key)
          invalid_config('missing the following key: ' + key)
        end
      end
    end

    def invalid_config(message)
      @logger.error('[config] -- configuration invalid -- ' + message)
      raise 'configuration invalid, ' + message
    end

    def self.read_arguments(arguments)
      options = Hash.new
      optparse = OptionParser.new do |opts|
        opts.on('-h', '--help', 'Display this screen') do
          puts opts
          exit
        end
        current_process = $0.split('/').last
        if current_process == 'sensu-server' || current_process == 'rake'
          opts.on('-w', '--worker', 'Only consume jobs, no check publishing (default: false)') do
            options[:worker] = true
          end
        end
        opts.on('-c', '--config FILE', 'Sensu JSON config FILE (default: /etc/sensu/config.json)') do |file|
          options[:config_file] = file
        end
        opts.on('-l', '--log FILE', 'Sensu log FILE (default: /tmp/sensu.log)') do |file|
          options[:log_file] = file
        end
        opts.on('-v', '--verbose', 'Enable verbose logging (default: false)') do
          options[:verbose] = true
        end
      end
      optparse.parse!(arguments)
      options
    end
  end
end
