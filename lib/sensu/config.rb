require File.join(File.dirname(__FILE__), 'helpers', 'ruby')

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'bundler'
require 'bundler/setup'

gem 'eventmachine', '~> 1.0.0.beta.4'

require 'optparse'
require 'json'
require 'hashie'
require 'amqp'
require 'cabin'
require 'cabin/outputs/em-stdlib-logger'

module Sensu
  class Config
    attr_accessor :settings, :logger

    DEFAULT_OPTIONS = {
      :log_file => '/tmp/sensu.log',
      :config_file => '/etc/sensu/config.json',
      :config_dir => '/etc/sensu/conf.d',
      :validate => true,
      :daemonize => false
    }

    def initialize(options={})
      @options = DEFAULT_OPTIONS.merge(options)
      if options[:log_file]
        open_log
      end
      read_config
      if @options[:validate]
        validate_config
      end
    end

    def open_log
      @logger = Cabin::Channel.new
      if File.writable?(@options[:log_file]) || !File.exist?(@options[:log_file]) && File.writable?(File.dirname(@options[:log_file]))
        ruby_logger = case @options[:service]
        when 'rake'
          Logger.new(@options[:log_file])
        else
          STDOUT.reopen(@options[:log_file], 'a')
          STDERR.reopen(STDOUT)
          STDOUT.sync = true
          Logger.new(STDOUT)
        end
      else
        invalid_config('log file is not writable: ' + @options[:log_file])
      end
      @logger.subscribe(Cabin::Outputs::EmStdlibLogger.new(ruby_logger))
      @logger.level = @options[:verbose] ? :debug : :info
      Signal.trap('USR1') do
        @logger.level = @logger.level == :info ? :debug : :info
      end
      @logger
    end

    def read_config
      if File.readable?(@options[:config_file])
        begin
          @settings = Hashie::Mash.new(JSON.parse(File.open(@options[:config_file], 'r').read))
        rescue JSON::ParserError => error
          invalid_config('configuration file (' + @options[:config_file] + ') must be valid JSON: ' + error.to_s)
        end
      else
        invalid_config('configuration file does not exist or is not readable: ' + @options[:config_file])
      end
      if File.exists?(@options[:config_dir])
        Dir[@options[:config_dir] + '/**/*.json'].each do |snippet_file|
          begin
            snippet_hash = JSON.parse(File.open(snippet_file, 'r').read)
          rescue JSON::ParserError => error
            invalid_config('configuration snippet file (' + snippet_file + ') must be valid JSON: ' + error.to_s)
          end
          merged_settings = @settings.to_hash.deep_merge(snippet_hash)
          if @logger
            @logger.warn('[settings] configuration snippet (' + snippet_file + ') applied changes: ' + @settings.deep_diff(merged_settings).to_json)
          end
          @settings = Hashie::Mash.new(merged_settings)
        end
      end
    end

    def validate_config
      if @logger
        @logger.debug('[config] -- validating configuration')
      end
      has_keys(%w[rabbitmq])
      case @options[:service]
      when 'server', 'rake'
        has_keys(%w[redis handlers checks])
        unless @settings.handlers.include?('default')
          invalid_config('missing default handler')
        end
        @settings.handlers.each do |name, details|
          unless details.is_a?(Hash)
            invalid_config('hander details must be a hash ' + name)
          end
          unless details.key?('type')
            invalid_config('missing type for handler ' + name)
          end
          case details.type
          when 'pipe'
            unless details.key?('command')
              invalid_config('missing command for pipe handler ' + name)
            end
          when 'amqp'
            unless details.key?('exchange')
              invalid_config('missing exchange details for amqp handler ' + name)
            end
            unless details.exchange.key?('name')
              invalid_config('missing exchange name for amqp handler ' + name)
            end
          else
            invalid_config('unknown type for handler ' + name)
          end
        end
      when 'api', 'rake'
        has_keys(%w[redis api])
      when 'client', 'rake'
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
      if @logger
        @logger.debug('[config] -- configuration valid -- running ' + @options[:service])
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
      raise 'configuration invalid, ' + message
    end

    def self.read_arguments(arguments)
      options = {
        :service => File.basename($0).split('-').last,
        :pid_file => '/tmp/' + File.basename($0) + '.pid',
      }
      optparse = OptionParser.new do |opts|
        opts.on('-h', '--help', 'Display this screen') do
          puts opts
          exit
        end
        opts.on('-c', '--config FILE', 'Sensu JSON config FILE (default: /etc/sensu/config.json)') do |file|
          options[:config_file] = file
        end
        opts.on('-d', '--config_dir DIR', 'Directory for supplemental Sensu JSON config files (default: /etc/sensu/conf.d/)') do |dir|
          options[:config_dir] = dir
        end
        opts.on('-l', '--log FILE', 'Sensu log FILE (default: /tmp/sensu.log)') do |file|
          options[:log_file] = file
        end
        opts.on('-v', '--verbose', 'Enable verbose logging (default: false)') do
          options[:verbose] = true
        end
        opts.on('-b', '--background', 'Fork into backgaround (daemon mode) (default: false)') do
          options[:daemonize] = true
        end
        opts.on('-p', '--pid_file FILE', 'Sensu PID FILE (default: ' + DEFAULT_OPTIONS[:pid_file] + ')') do |file|
          options[:pid_file] = file
        end
      end
      optparse.parse!(arguments)
      DEFAULT_OPTIONS.merge(options)
    end
  end
end
