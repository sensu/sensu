require 'rubygems'
require 'bundler'
require 'bundler/setup'

gem 'eventmachine', '~> 1.0.0.beta.4'

require 'optparse'
require 'time'
require 'json'
require 'hashie'
require 'amqp'
require 'cabin'
require 'cabin/outputs/em/stdlib-logger'

require File.join(File.dirname(__FILE__), 'version')
require File.join(File.dirname(__FILE__), 'patches', 'ruby')
require File.join(File.dirname(__FILE__), 'patches', 'amqp')

if ENV['RBTRACE']
  require 'rbtrace'
end

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

    def invalid_config(message)
      puts 'CONFIGURATION INVALID: ' + message
      puts 'SENSU NOT RUNNING'
      exit 2
    end

    def setup_logging
      if @options[:log_file]
        if File.writable?(@options[:log_file]) || !File.exist?(@options[:log_file]) && File.writable?(File.dirname(@options[:log_file]))
          STDOUT.reopen(@options[:log_file], 'a')
          STDERR.reopen(STDOUT)
          STDOUT.sync = true
        else
          invalid_config('log file is not writable: ' + @options[:log_file])
        end
      end
      @logger = Cabin::Channel.new
      log_output = File.basename($0) == 'rake' ? '/tmp/sensu-test.log' : STDOUT
      @logger.subscribe(Cabin::Outputs::EM::StdlibLogger.new(Logger.new(log_output)))
      @logger.level = @options[:verbose] ? :debug : :info
      if Signal.list.include?('USR1')
        Signal.trap('USR1') do
          @logger.level = @logger.level == :info ? :debug : :info
        end
      end
    end

    def validate_common_settings
      @settings.checks.each do |name, details|
        if details.key?('status') || details.key?('output')
          invalid_config('reserved key (output or status) defined in check ' + name)
        end
        unless details.interval.is_a?(Integer) && details.interval > 0
          invalid_config('missing interval for check ' + name)
        end
        unless details.command.is_a?(String)
          invalid_config('missing command for check ' + name)
        end
        unless details.standalone
          unless details.subscribers.is_a?(Array) && details.subscribers.count > 0
            invalid_config('missing subscribers for check ' + name)
          end
          details.subscribers.each do |subscriber|
            unless subscriber.is_a?(String) && !subscriber.empty?
              invalid_config('a check subscriber must be a string (not empty) for check ' + name)
            end
          end
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
    end

    def validate_server_settings
      unless @settings.handlers.include?('default')
        invalid_config('missing default handler')
      end
      @settings.handlers.each do |name, details|
        unless details.is_a?(Hash)
          invalid_config('handler details must be a hash for handler ' + name)
        end
        unless details['type'].is_a?(String)
          invalid_config('missing type for handler ' + name)
        end
        case details['type']
        when 'pipe'
          unless details.command.is_a?(String)
            invalid_config('missing command for pipe handler ' + name)
          end
        when 'amqp'
          unless details.exchange.is_a?(Hash)
            invalid_config('missing exchange details for amqp handler ' + name)
          end
          unless details.exchange.name.is_a?(String)
            invalid_config('missing exchange name for amqp handler ' + name)
          end
          if details.exchange.key?('type')
            unless %w[direct fanout topic].include?(details.exchange['type'])
              invalid_config('invalid exchange type for amqp handler ' + name)
            end
          end
        when 'set'
          unless details.handlers.is_a?(Array) && details.handlers.count > 0
            invalid_config('missing handler set for handler ' + name)
          end
        else
          invalid_config('unknown type for handler ' + name)
        end
      end
    end

    def validate_api_settings
      unless @settings.api.port.is_a?(Integer)
        invalid_config('api port must be an integer')
      end
      if @settings.api.key?('user') || @settings.api.key?('password')
        unless @settings.api.user.is_a?(String)
          invalid_config('api user must be a string')
        end
        unless @settings.api.password.is_a?(String)
          invalid_config('api password must be a string')
        end
      end
    end

    def validate_client_settings
      unless @settings.client.name.is_a?(String)
        invalid_config('client must have a name')
      end
      unless @settings.client.address.is_a?(String)
        invalid_config('client must have an address (ip or hostname)')
      end
      unless @settings.client.subscriptions.is_a?(Array) && @settings.client.subscriptions.count > 0
        invalid_config('client must have subscriptions')
      end
      @settings.client.subscriptions.each do |subscription|
        unless subscription.is_a?(String) && !subscription.empty?
          invalid_config('a client subscription must be a string (not empty)')
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

    def validate_settings
      @logger.debug('[validate] -- validating configuration')
      has_keys(%w[checks])
      validate_common_settings
      case File.basename($0)
      when 'rake'
        has_keys(%w[api handlers client])
        validate_server_settings
        validate_api_settings
        validate_client_settings
      when 'sensu-server'
        has_keys(%w[handlers])
        validate_server_settings
      when 'sensu-api'
        has_keys(%w[api])
        validate_api_settings
      when 'sensu-client'
        has_keys(%w[client])
        validate_client_settings
      end
      @logger.info('[validate] -- configuration valid -- running')
    end

    def setup_settings
      if File.readable?(@options[:config_file])
        begin
          config_hash = JSON.parse(File.open(@options[:config_file], 'r').read)
          %w[rabbitmq redis].each do |key|
            config_hash[key] ||= Hash.new
          end
        rescue JSON::ParserError => error
          invalid_config('configuration file (' + @options[:config_file] + ') must be valid json: ' + error.to_s)
        end
        @settings = Hashie::Mash.new(config_hash)
      else
        invalid_config('configuration file does not exist or is not readable: ' + @options[:config_file])
      end
      if File.exists?(@options[:config_dir])
        Dir[@options[:config_dir] + '/**/*.json'].each do |snippet_file|
          if File.readable?(snippet_file)
            begin
              snippet_hash = JSON.parse(File.open(snippet_file, 'r').read)
            rescue JSON::ParserError => error
              invalid_config('configuration snippet file (' + snippet_file + ') must be valid json: ' + error.to_s)
            end
            merged_settings = @settings.to_hash.deep_merge(snippet_hash)
            @logger.warn('[settings] -- configuration snippet (' + snippet_file + ') applied changes: ' + @settings.deep_diff(merged_settings).to_json)
            @settings = Hashie::Mash.new(merged_settings)
          else
            invalid_config('configuration snippet file is not readable: ' + snippet_file)
          end
        end
      end
      validate_settings
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
