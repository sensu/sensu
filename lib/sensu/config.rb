require 'rubygems'

gem 'eventmachine', '~> 1.0.0.beta.4'

require 'optparse'
require 'time'
require 'uri'
require 'json'
require 'hashie'
require 'amqp'
require 'cabin'

require File.join(File.dirname(__FILE__), 'version')
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

    def validate_common_settings
      @settings.checks.each do |name, details|
        unless details.interval.is_a?(Integer) && details.interval > 0
          invalid_config('missing interval for check: ' + name)
        end
        unless details.command.is_a?(String)
          invalid_config('missing command for check: ' + name)
        end
        unless details.standalone
          unless details.subscribers.is_a?(Array) && details.subscribers.count > 0
            invalid_config('missing subscribers for check: ' + name)
          end
          details.subscribers.each do |subscriber|
            unless subscriber.is_a?(String) && !subscriber.empty?
              invalid_config('a check subscriber must be a string for check: ' + name)
            end
          end
        end
        if details.key?('handler')
          unless details.handler.is_a?(String)
            invalid_config('handler must be a string for check: ' + name)
          end
        end
        if details.key?('handlers')
          unless details.handlers.is_a?(Array)
            invalid_config('handlers must be an array for check: ' + name)
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
        invalid_config('client must have an address')
      end
      unless @settings.client.subscriptions.is_a?(Array) && @settings.client.subscriptions.count > 0
        invalid_config('client must have subscriptions')
      end
      @settings.client.subscriptions.each do |subscription|
        unless subscription.is_a?(String) && !subscription.empty?
          invalid_config('a client subscription must be a string')
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
      @logger.debug('config valid')
    end

    def env_settings
      settings = Hash.new
      %w[api rabbitmq redis].each do |key|
        settings[key] = Hash.new
      end
      begin
        amqp = ENV["RABBITMQ_URL"] ? URI(ENV["RABBITMQ_URL"]) : nil
      rescue
        @logger.error('rabbitmq url environment variable is invalid', {
          :variable => 'RABBITMQ_URL'
        })
      end
      unless amqp.nil?
        settings[:rabbitmq][:host] = amqp.host
        settings[:rabbitmq][:port] = amqp.port
        settings[:rabbitmq][:vhost] = amqp.path.gsub(/^[\/]/,"")
        unless amqp.user.nil?
          settings[:rabbitmq][:user] = amqp.user
        end
        unless amqp.password.nil?
          settings[:rabbitmq][:password] = amqp.password
        end
      end
      begin
        ENV["REDIS_URL"] ||= ENV["REDISTOGO_URL"]
        redis = ENV["REDIS_URL"] ? URI(ENV["REDIS_URL"]) : nil
      rescue
        @logger.error('redis url environment variable is invalid', {
          :variables => %w[REDIS_URL REDISTOGO_URL]
        })
      end
      unless redis.nil?
        settings[:redis][:host] = redis.host
        settings[:redis][:port] = redis.port
        unless redis.user.nil?
          settings[:redis][:user] = redis.user
        end
        unless redis.password.nil?
          settings[:redis][:password] = redis.password
        end
      end
      ENV["API_PORT"] ||= ENV["PORT"]
      if ENV["API_PORT"]
        settings[:api][:port] = Integer(ENV["API_PORT"])
      end
      settings
    end

    def setup_settings
      settings = env_settings
      if File.readable?(@options[:config_file])
        begin
          config_contents = File.open(@options[:config_file], 'r').read
          config = JSON.parse(config_contents, :symbolize_names => true)
          settings = settings.deep_merge(config)
        rescue JSON::ParserError => error
          @logger.error('config file must be valid json', {
            :config_file => @options[:config_file],
            :error => error.to_s
          })
          @logger.warn('ignoring config file', {
            :config_file => @options[:config_file]
          })
        end
      else
        @logger.error('config file does not exist or is not readable', {
          :config_file => @options[:config_file]
        })
        @logger.warn('ignoring config file', {
          :config_file => @options[:config_file]
        })
      end
      Dir[@options[:config_dir] + '/**/*.json'].each do |snippet_file|
        if File.readable?(snippet_file)
          begin
            config_contents = File.open(snippet_file, 'r').read
            config = JSON.parse(config_contents, :symbolize_names => true)
            merged_settings = settings.deep_merge(config)
            @logger.warn('config file applied changes', {
              :config_file => snippet_file,
              :changes => settings.deep_diff(merged_settings)
            })
            settings = merged_settings
          rescue JSON::ParserError => error
            @logger.error('config file must be valid json', {
              :config_file => snippet_file,
              :error => error.to_s
            })
            @logger.warn('ignoring config file', {
              :config_file => snippet_file
            })
          end
        else
          @logger.error('config file is not readable', {
            :config_file => snippet_file
          })
          @logger.warn('ignoring config file', {
            :config_file => snippet_file
          })
        end
      end
      @settings = Hashie::Mash.new(settings)
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
