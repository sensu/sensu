require 'rubygems'

gem 'multi_json', '1.10.1'

gem 'sensu-em', '2.4.0'
gem 'sensu-logger', '1.0.0'
gem 'sensu-settings', '1.2.0'
gem 'sensu-extension', '1.0.0'
gem 'sensu-extensions', '1.0.0'
gem 'sensu-transport', '2.4.0'
gem 'sensu-spawn', '1.1.0'

require 'time'
require 'uri'

require 'sensu/logger'
require 'sensu/settings'
require 'sensu/extensions'
require 'sensu/transport'
require 'sensu/spawn'

require 'sensu/constants'
require 'sensu/utilities'
require 'sensu/cli'
require 'sensu/redis'

MultiJson.load_options = {:symbolize_keys => true}

module Sensu
  module Daemon
    include Utilities

    attr_reader :state

    def initialize(options={})
      @state = :initializing
      @timers = {
        :run => Array.new
      }
      setup_logger(options)
      load_settings(options)
      load_extensions(options)
      setup_process(options)
    end

    def setup_logger(options={})
      @logger = Logger.get(options)
      @logger.setup_signal_traps
    end

    def log_concerns(concerns=[], level=:warn)
      concerns.each do |concern|
        message = concern.delete(:message)
        @logger.send(level, message, redact_sensitive(concern))
      end
    end

    def load_settings(options={})
      @settings = Settings.get(options)
      log_concerns(@settings.warnings)
      failures = @settings.validate
      unless failures.empty?
        @logger.fatal('invalid settings')
        log_concerns(failures, :fatal)
        @logger.fatal('SENSU NOT RUNNING!')
        exit 2
      end
    end

    def load_extensions(options={})
      @extensions = Extensions.get(options)
      log_concerns(@extensions.warnings)
      extension_settings = @settings.to_hash.dup
      @extensions.all.each do |extension|
        extension.logger = @logger
        extension.settings = extension_settings
      end
    end

    def setup_process(options)
      if options[:daemonize]
        daemonize
      end
      if options[:pid_file]
        write_pid(options[:pid_file])
      end
    end

    def start
      @state = :running
    end

    def pause
      @state = :paused
    end

    def resume
      @state = :running
    end

    def stop
      @state = :stopped
      @logger.warn('stopping reactor')
      EM::stop_event_loop
    end

    def setup_signal_traps
      @signals = Array.new
      STOP_SIGNALS.each do |signal|
        Signal.trap(signal) do
          @signals << signal
        end
      end
      EM::PeriodicTimer.new(1) do
        signal = @signals.shift
        if STOP_SIGNALS.include?(signal)
          @logger.warn('received signal', {
            :signal => signal
          })
          stop
        end
      end
    end

    def setup_transport
      transport_name = @settings[:transport][:name] || 'rabbitmq'
      transport_settings = @settings[transport_name]
      @logger.debug('connecting to transport', {
        :name => transport_name,
        :settings => transport_settings
      })
      Transport.logger = @logger
      @transport = Transport.connect(transport_name, transport_settings)
      @transport.on_error do |error|
        @logger.fatal('transport connection error', {
          :error => error.to_s
        })
        stop
      end
      @transport.before_reconnect do
        unless testing?
          @logger.warn('reconnecting to transport')
          pause
        end
      end
      @transport.after_reconnect do
        @logger.info('reconnected to transport')
        resume
      end
    end

    def setup_redis
      @logger.debug('connecting to redis', {
        :settings => @settings[:redis]
      })
      @redis = Redis.connect(@settings[:redis])
      @redis.on_error do |error|
        @logger.fatal('redis connection error', {
          :error => error.to_s
        })
        stop
      end
      @redis.before_reconnect do
        unless testing?
          @logger.warn('reconnecting to redis')
          pause
        end
      end
      @redis.after_reconnect do
        @logger.info('reconnected to redis')
        resume
      end
    end

    private

    def write_pid(file)
      begin
        File.open(file, 'w') do |pid_file|
          pid_file.puts(Process.pid)
        end
      rescue
        @logger.fatal('could not write to pid file', {
          :pid_file => file
        })
        @logger.fatal('SENSU NOT RUNNING!')
        exit 2
      end
    end

    def daemonize
      Kernel.srand
      if Kernel.fork
        exit
      end
      unless Process.setsid
        @logger.fatal('cannot detach from controlling terminal')
        @logger.fatal('SENSU NOT RUNNING!')
        exit 2
      end
      Signal.trap('SIGHUP', 'IGNORE')
      if Kernel.fork
        exit
      end
      Dir.chdir('/')
      ObjectSpace.each_object(IO) do |io|
        unless [STDIN, STDOUT, STDERR].include?(io)
          begin
            unless io.closed?
              io.close
            end
          rescue
          end
        end
      end
    end
  end
end
