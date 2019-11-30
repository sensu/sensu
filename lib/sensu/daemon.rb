require "rubygems"

gem "eventmachine", "1.2.7"

gem "sensu-json", "2.1.1"
gem "sensu-logger", "1.2.2"
gem "sensu-settings", "10.17.0"
gem "sensu-extension", "1.5.2"
gem "sensu-extensions", "1.11.0"
gem "sensu-transport", "8.3.0"
gem "sensu-spawn", "2.5.0"
gem "sensu-redis", "2.4.0"

require "time"
require "uri"

if RUBY_PLATFORM =~ /aix/ || RUBY_PLATFORM =~ /solaris/
  require "em/pure_ruby"
end

require "sensu/json"
require "sensu/logger"
require "sensu/settings"
require "sensu/extensions"
require "sensu/transport"
require "sensu/spawn"
require "sensu/redis"

require "sensu/constants"
require "sensu/utilities"
require "sensu/cli"

module Sensu
  module Daemon
    include Utilities

    attr_reader :start_time, :settings

    # Initialize the Sensu process. Set the start time, initial
    # service state, double the maximum number of EventMachine timers,
    # set up the logger, and load settings. This method will load
    # extensions and setup Sensu Spawn if the Sensu process is not the
    # Sensu API. This method can and optionally daemonize the process
    # and/or create a PID file.
    #
    # @param options [Hash]
    def initialize(options={})
      @start_time = Time.now.to_i
      @state = :initializing
      @timers = {:run => []}
      unless EM::reactor_running?
        EM::epoll
        EM::set_max_timers(200000)
        EM::error_handler do |error|
          unexpected_error(error)
        end
      end
      setup_logger(options)
      load_settings(options)
      unless sensu_service_name == "api"
        load_extensions(options)
        setup_spawn
      end
      setup_process(options)
    end

    # Handle an unexpected error. This method is used for EM global
    # catch-all error handling, accepting an error object. Error
    # handling is opt-in via a configuration option, e.g. `"sensu":
    # {"global_error_handler": true}`. If a user does not opt-in, the
    # provided error will be raised (uncaught). If a user opts-in via
    # configuration, the error will be logged and ignored :itsfine:.
    #
    # @param error [Object]
    def unexpected_error(error)
      if @settings && @settings[:sensu][:global_error_handler]
        backtrace = error.backtrace.join("\n")
        if @logger
          @logger.warn("global catch-all error handling enabled")
          @logger.fatal("unexpected error - please address this immediately", {
            :error => error.to_s,
            :error_class => error.class,
            :backtrace => backtrace
          })
        else
          puts "global catch-all error handling enabled"
          puts "unexpected error - please address this immediately: #{error.to_s}\n#{error.class}\n#{backtrace}"
        end
      else
        raise error
      end
    end

    # Set up the Sensu logger and its process signal traps for log
    # rotation and debug log level toggling. This method creates the
    # logger instance variable: `@logger`.
    #
    # https://github.com/sensu/sensu-logger
    #
    # @param options [Hash]
    def setup_logger(options={})
      @logger = Logger.get(options)
      @logger.setup_signal_traps
    end

    # Log setting or extension loading notices, sensitive information
    # is redacted.
    #
    # @param notices [Array] to be logged.
    # @param level [Symbol] to log the notices at.
    def log_notices(notices=[], level=:warn)
      notices.each do |concern|
        message = concern.delete(:message)
        @logger.send(level, message, redact_sensitive(concern))
      end
    end

    # Determine if the Sensu settings are valid, if there are load or
    # validation errors, and immediately exit the process with the
    # appropriate exit status code. This method is used to determine
    # if the latest configuration changes are valid prior to
    # restarting the Sensu service, triggered by a CLI argument, e.g.
    # `--validate_config`.
    #
    # @param settings [Object]
    def validate_settings!(settings)
      if settings.errors.empty?
        puts "configuration is valid"
        exit
      else
        puts "configuration is invalid"
        puts Sensu::JSON.dump({:errors => @settings.errors}, :pretty => true)
        exit 2
      end
    end

    # Print the Sensu settings (JSON) to STDOUT and immediately exit
    # the process with the appropriate exit status code. This method
    # is used while troubleshooting configuration issues, triggered by
    # a CLI argument, e.g. `--print_config`. Sensu settings with
    # sensitive values (e.g. passwords) are first redacted.
    #
    # @param settings [Object]
    def print_settings!(settings)
      redacted_settings = redact_sensitive(settings.to_hash)
      @logger.warn("outputting compiled configuration and exiting")
      puts Sensu::JSON.dump(redacted_settings, :pretty => true)
      exit(settings.errors.empty? ? 0 : 2)
    end

    # Load Sensu settings. This method creates the settings instance
    # variable: `@settings`. If the `validate_config` option is true,
    # this method calls `validate_settings!()` to validate the latest
    # compiled configuration settings and will then exit the process.
    # If the `print_config` option is true, this method calls
    # `print_settings!()` to output the compiled configuration
    # settings and will then exit the process. If there are loading or
    # validation errors, they will be logged (notices), and this
    # method will exit(2) the process.
    #
    #
    # https://github.com/sensu/sensu-settings
    #
    # @param options [Hash]
    def load_settings(options={})
      @settings = Settings.get(options)
      validate_settings!(@settings) if options[:validate_config]
      log_notices(@settings.warnings)
      log_notices(@settings.errors, :fatal)
      print_settings!(@settings) if options[:print_config]
      unless @settings.errors.empty?
        @logger.fatal("SENSU NOT RUNNING!")
        exit 2
      end
      @settings.set_env!
    end

    # Load Sensu extensions and log any notices. Set the logger and
    # settings for each extension instance. This method creates the
    # extensions instance variable: `@extensions`.
    #
    # https://github.com/sensu/sensu-extensions
    # https://github.com/sensu/sensu-extension
    #
    # @param options [Hash]
    def load_extensions(options={})
      extensions_options = options.merge(:extensions => @settings[:extensions])
      @extensions = Extensions.get(extensions_options)
      log_notices(@extensions.warnings)
      extension_settings = @settings.to_hash.dup
      @extensions.all.each do |extension|
        extension.logger = @logger
        extension.settings = extension_settings
      end
    end

    # Set up Sensu spawn, creating a worker to create, control, and
    # limit spawned child processes. This method adjusts the
    # EventMachine thread pool size to accommodate the concurrent
    # process spawn limit and other Sensu process operations.
    #
    # https://github.com/sensu/sensu-spawn
    def setup_spawn
      @logger.info("configuring sensu spawn", :settings => @settings[:sensu][:spawn])
      threadpool_size = @settings[:sensu][:spawn][:limit] + 10
      @logger.debug("setting eventmachine threadpool size", :size => threadpool_size)
      EM::threadpool_size = threadpool_size
      Spawn.setup(@settings[:sensu][:spawn])
    end

    # Manage the current process, optionally daemonize and/or write
    # the current process ID to a PID file.
    #
    # @param options [Hash]
    def setup_process(options)
      daemonize if options[:daemonize]
      write_pid(options[:pid_file]) if options[:pid_file]
    end

    # Start the Sensu service and set the service state to `:running`.
    # This method will likely be overridden by a subclass. Yield if a
    # block is provided.
    def start
      @state = :running
      yield if block_given?
    end

    # Pause the Sensu service and set the service state to `:paused`.
    # This method will likely be overridden by a subclass.
    def pause
      @state = :paused
    end

    # Resume the paused Sensu service and set the service state to
    # `:running`. This method will likely be overridden by a subclass.
    def resume
      @state = :running
    end

    # Stop the Sensu service and set the service state to `:stopped`.
    # This method will likely be overridden by a subclass. This method
    # should stop the EventMachine event loop.
    def stop
      @state = :stopped
      @logger.warn("stopping reactor")
      EM::stop_event_loop
    end

    # Set up process signal traps. This method uses the `STOP_SIGNALS`
    # constant to determine which process signals will result in a
    # graceful service stop. A periodic timer must be used to poll for
    # received signals, as Mutex#lock cannot be used within the
    # context of `trap()`.
    def setup_signal_traps
      @signals = []
      STOP_SIGNALS.each do |signal|
        Signal.trap(signal) do
          @signals << signal
        end
      end
      EM::PeriodicTimer.new(1) do
        signal = @signals.shift
        if STOP_SIGNALS.include?(signal)
          @logger.warn("received signal", :signal => signal)
          stop
        end
      end
    end

    # Set up the Sensu transport connection. Sensu uses a transport
    # API, allowing it to use various message brokers. By default,
    # Sensu will use the built-in "rabbitmq" transport. The Sensu
    # service will stop gracefully in the event of a transport error,
    # and pause/resume in the event of connectivity issues. This
    # method creates the transport instance variable: `@transport`.
    #
    # https://github.com/sensu/sensu-transport
    #
    # @yield [Object] passes initialized and connected Transport
    #   connection object to the callback/block.
    def setup_transport
      transport_name = @settings[:transport][:name]
      transport_settings = @settings[transport_name]
      @logger.debug("connecting to transport", {
        :name => transport_name,
        :settings => transport_settings
      })
      Transport.logger = @logger
      Transport.connect(transport_name, transport_settings) do |connection|
        @transport = connection
        @transport.on_error do |error|
          @logger.error("transport connection error", :error => error.to_s)
          if @settings[:transport][:reconnect_on_error]
            @transport.reconnect
          else
            stop
          end
        end
        @transport.before_reconnect do
          unless testing?
            @logger.warn("reconnecting to transport")
            pause
          end
        end
        @transport.after_reconnect do
          @logger.info("reconnected to transport")
          resume
        end
        yield(@transport) if block_given?
      end
    end

    # Set up the Redis connection. Sensu uses Redis as a data store,
    # to store the client registry, current events, etc. The Sensu
    # service will stop gracefully in the event of a Redis error, and
    # pause/resume in the event of connectivity issues. This method
    # creates the Redis instance variable: `@redis`.
    #
    # https://github.com/sensu/sensu-redis
    #
    # @yield [Object] passes initialized and connected Redis
    #   connection object to the callback/block.
    def setup_redis
      @logger.debug("connecting to redis", :settings => @settings[:redis])
      Redis.logger = @logger
      Redis.connect(@settings[:redis]) do |connection|
        @redis = connection
        @redis.on_error do |error|
          @logger.error("redis connection error", :error => error.to_s)
        end
        @redis.before_reconnect do
          unless testing?
            @logger.warn("reconnecting to redis")
            pause
          end
        end
        @redis.after_reconnect do
          @logger.info("reconnected to redis")
          resume
        end
        yield(@redis) if block_given?
      end
    end

    private

    # Get the Sensu service name.
    #
    # @return [String] Sensu service name.
    def sensu_service_name
      File.basename($0).split("-").last
    end

    # Write the current process ID (PID) to a file (PID file). This
    # method will cause the Sensu service to exit (2) if the PID file
    # cannot be written to.
    #
    # @param file [String] to write the current PID to.
    def write_pid(file)
      begin
        File.open(file, "w") do |pid_file|
          pid_file.puts(Process.pid)
        end
      rescue
        @logger.fatal("could not write to pid file", :pid_file => file)
        @logger.fatal("SENSU NOT RUNNING!")
        exit 2
      end
    end

    # Daemonize the current process. Seed the random number generator,
    # fork (& exit), detach from controlling terminal, ignore SIGHUP,
    # fork (& exit), use root '/' as the current working directory,
    # and close STDIN/OUT/ERR since the process is no longer attached
    # to a terminal.
    def daemonize
      Kernel.srand
      exit if Kernel.fork
      unless Process.setsid
        @logger.fatal("cannot detach from controlling terminal")
        @logger.fatal("SENSU NOT RUNNING!")
        exit 2
      end
      Signal.trap("SIGHUP", "IGNORE")
      exit if Kernel.fork
      Dir.chdir("/")
      ObjectSpace.each_object(IO) do |io|
        unless [STDIN, STDOUT, STDERR].include?(io)
          begin
            io.close unless io.closed?
          rescue; end
        end
      end
    end
  end
end
