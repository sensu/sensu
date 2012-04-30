require 'rubygems'

gem 'eventmachine', '~> 1.0.0.beta.4'

require 'optparse'
require 'uri'
require 'json'
require 'hashie'
require 'amqp'
require 'cabin'

require File.join(File.dirname(__FILE__), 'version')
require File.join(File.dirname(__FILE__), 'settings')
require File.join(File.dirname(__FILE__), 'patches', 'ruby')
require File.join(File.dirname(__FILE__), 'patches', 'amqp')

module Sensu
  class Config
    attr_accessor :logger, :settings

    DEFAULT_OPTIONS = {
      :config_file => '/etc/sensu/config.json',
      :config_dir => '/etc/sensu/conf.d'
    }

    def initialize(options={})
      @options = DEFAULT_OPTIONS.merge(options)
      setup_logging
      setup_settings
    end

    def setup_logging
      @logger = Cabin::Channel.get
      @logger.subscribe(STDOUT)
      @logger.level = @options[:log_level] || (@options[:verbose] ? :debug : :info)
      if Signal.list.include?('USR1')
        Signal.trap('USR1') do
          @logger.level = @logger.level == :info ? :debug : :info
        end
      end
      if @options[:log_file]
        if File.writable?(@options[:log_file]) || !File.exist?(@options[:log_file]) && File.writable?(File.dirname(@options[:log_file]))
          STDOUT.reopen(@options[:log_file], 'a')
          STDERR.reopen(STDOUT)
          STDOUT.sync = true
        else
          @logger.error('log file is not writable', {
            :log_file => @options[:log_file]
          })
        end
      end
    end

    def invalid_config(message)
      @logger.fatal('CONFIG INVALID!', {
        :reason => message
      })
      @logger.fatal('SENSU NOT RUNNING!')
      exit 2
    end

    def validate_server_settings
      unless @settings.handlers.include?('default')
        invalid_config('missing default handler')
      end
      @settings.handlers.each do |name, details|
        unless details.is_a?(Hash)
          invalid_config('handler details must be a hash for handler: ' + name)
        end
        unless details['type'].is_a?(String)
          invalid_config('missing type for handler: ' + name)
        end
        case details['type']
        when 'pipe'
          unless details.command.is_a?(String)
            invalid_config('missing command for pipe handler: ' + name)
          end
        when 'amqp'
          unless details.exchange.is_a?(Hash)
            invalid_config('missing exchange details for amqp handler: ' + name)
          end
          unless details.exchange.name.is_a?(String)
            invalid_config('missing exchange name for amqp handler: ' + name)
          end
          if details.exchange.key?('type')
            unless %w[direct fanout topic].include?(details.exchange['type'])
              invalid_config('invalid exchange type for amqp handler: ' + name)
            end
          end
        when 'set'
          unless details.handlers.is_a?(Array) && details.handlers.count > 0
            invalid_config('missing handler set for handler: ' + name)
          end
        else
          invalid_config('unknown type for handler: ' + name)
        end
      end
    end

    def has_keys(keys)
      keys.each do |key|
        unless @settings.key?(key)
          invalid_config('missing the following key: ' + key)
        end
      end
    end

    def validate_config
      @logger.debug('validating config')
      has_keys(%w[checks])
      case File.basename($0)
      when 'rake'
        has_keys(%w[handlers])
        validate_server_settings
      when 'sensu-server'
        has_keys(%w[handlers])
        validate_server_settings
      end
      @logger.debug('config valid')
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
        invalid_config(error)
      end
      @settings = Mash.new(settings.to_hash)
      validate_config
    end

    def self.read_arguments(arguments)
      options = Hash.new
      optparse = OptionParser.new do |opts|
        opts.on('-h', '--help', 'Display this message') do
          puts opts
          exit
        end
        opts.on('-V', '--version', 'Display version') do
          puts Sensu::VERSION
          exit
        end
        opts.on('-c', '--config FILE', 'Sensu JSON config FILE. Default is /etc/sensu/config.json') do |file|
          options[:config_file] = file
        end
        opts.on('-d', '--config_dir DIR', 'DIR for supplemental Sensu JSON config files. Default is /etc/sensu/conf.d/') do |dir|
          options[:config_dir] = dir
        end
        opts.on('-l', '--log FILE', 'Log to a given FILE. Default is to log to stdout') do |file|
          options[:log_file] = file
        end
        opts.on('-v', '--verbose', 'Enable verbose logging') do
          options[:verbose] = true
        end
        opts.on('-b', '--background', 'Fork into the background') do
          options[:daemonize] = true
        end
        opts.on('-p', '--pid_file FILE', 'Write the PID to a given FILE') do |file|
          options[:pid_file] = file
        end
      end
      optparse.parse!(arguments)
      DEFAULT_OPTIONS.merge(options)
    end
  end
end
