require File.join(File.dirname(__FILE__), 'base')
require File.join(File.dirname(__FILE__), 'socket')

module Sensu
  class Client
    include Utilities

    attr_accessor :safe_mode

    def self.run(options={})
      client = self.new(options)
      EM::run do
        client.start
        client.trap_signals
      end
    end

    def initialize(options={})
      base = Base.new(options)
      @logger = base.logger
      @settings = base.settings
      @extensions = base.extensions
      base.setup_process
      @extensions.load_settings(@settings.to_hash)
      @timers = Array.new
      @checks_in_progress = Array.new
      @safe_mode = @settings[:client][:safe_mode] || false
    end

    def setup_transport
      transport_name = @settings[:transport] || 'rabbitmq'
      transport_settings = @settings[transport_name.to_sym]
      @logger.debug('connecting to transport', {
        :name => transport_name,
        :settings => transport_settings
      })
      @transport = Transport.connect(transport_name, transport_settings)
      @transport.logger = @logger
      @transport.on_error do |error|
        @logger.fatal('transport connection error', {
          :error => error.to_s
        })
        stop
      end
      @transport.before_reconnect do
        @logger.warn('reconnecting to transport')
      end
      @transport.after_reconnect do
        @logger.info('reconnected to transport')
      end
    end

    def publish_keepalive
      keepalive = @settings[:client].merge(:timestamp => Time.now.to_i)
      payload = redact_sensitive(keepalive, @settings[:client][:redact])
      @logger.debug('publishing keepalive', {
        :payload => payload
      })
      @transport.publish(:direct, 'keepalives', Oj.dump(payload)) do |info|
        if info[:error]
          @logger.error('failed to publish keepalive', {
            :payload => payload,
            :error => info[:error].to_s
          })
        end
      end
    end

    def setup_keepalives
      @logger.debug('scheduling keepalives')
      publish_keepalive
      @timers << EM::PeriodicTimer.new(20) do
        if @transport.connected?
          publish_keepalive
        end
      end
    end

    def publish_result(check)
      payload = {
        :client => @settings[:client][:name],
        :check => check
      }
      @logger.info('publishing check result', {
        :payload => payload
      })
      @transport.publish(:direct, 'results', Oj.dump(payload)) do |info|
        if info[:error]
          @logger.error('failed to publish check result', {
            :payload => payload,
            :error => info[:error].to_s
          })
        end
      end
    end

    def substitute_command_tokens(check)
      unmatched_tokens = Array.new
      substituted = check[:command].gsub(/:::([^:]*?):::/) do
        token, default = $1.to_s.split('|', -1)
        matched = token.split('.').inject(@settings[:client]) do |client, attribute|
          if client[attribute].nil?
            default.nil? ? break : default
          else
            client[attribute]
          end
        end
        if matched.nil?
          unmatched_tokens << token
        end
        matched
      end
      [substituted, unmatched_tokens]
    end

    def execute_check_command(check)
      @logger.debug('attempting to execute check command', {
        :check => check
      })
      unless @checks_in_progress.include?(check[:name])
        @checks_in_progress << check[:name]
        command, unmatched_tokens = substitute_command_tokens(check)
        check[:executed] = Time.now.to_i
        if unmatched_tokens.empty?
          execute = Proc.new do
            @logger.debug('executing check command', {
              :check => check
            })
            started = Time.now.to_f
            begin
              check[:output], check[:status] = IO.popen(command, 'r', check[:timeout])
            rescue => error
              check[:output] = 'Unexpected error: ' + error.to_s
              check[:status] = 2
            end
            check[:duration] = ('%.3f' % (Time.now.to_f - started)).to_f
            check
          end
          publish = Proc.new do |check|
            publish_result(check)
            @checks_in_progress.delete(check[:name])
          end
          EM::defer(execute, publish)
        else
          check[:output] = 'Unmatched command tokens: ' + unmatched_tokens.join(', ')
          check[:status] = 3
          check[:handle] = false
          publish_result(check)
          @checks_in_progress.delete(check[:name])
        end
      else
        @logger.warn('previous check command execution in progress', {
          :check => check
        })
      end
    end

    def run_check_extension(check)
      @logger.debug('attempting to run check extension', {
        :check => check
      })
      check[:executed] = Time.now.to_i
      extension = @extensions[:checks][check[:extension]]
      extension.safe_run(check) do |output, status|
        check[:output] = output
        check[:status] = status
        publish_result(check)
      end
    end

    def process_check(check)
      @logger.debug('processing check', {
        :check => check
      })
      if check.has_key?(:command)
        if @settings.check_exists?(check[:name])
          check.merge!(@settings[:checks][check[:name]])
          execute_check_command(check)
        elsif @safe_mode
          check[:output] = 'Check is not locally defined (safe mode)'
          check[:status] = 3
          check[:handle] = false
          check[:executed] = Time.now.to_i
          publish_result(check)
        else
          execute_check_command(check)
        end
      elsif check.has_key?(:extension)
        if @extensions.check_exists?(check[:extension])
          run_check_extension(check)
        else
          @logger.warn('unknown check extension', {
            :check => check
          })
        end
      end
    end

    def setup_subscriptions
      @logger.debug('subscribing to client subscriptions')
      @settings[:client][:subscriptions].each do |subscription|
        @logger.debug('subscribing to a subscription', {
          :subscription => subscription
        })
        funnel = [@settings[:client][:name], VERSION, Time.now.to_i].join('-')
        @transport.subscribe(:fanout, subscription, funnel) do |message_info, message|
          check = Oj.load(message)
          @logger.info('received check request', {
            :check => check
          })
          process_check(check)
        end
      end
    end

    def schedule_checks(checks)
      check_count = 0
      stagger = testing? ? 0 : 2
      checks.each do |check|
        check_count += 1
        scheduling_delay = stagger * check_count % 30
        @timers << EM::Timer.new(scheduling_delay) do
          interval = testing? ? 0.5 : check[:interval]
          @timers << EM::PeriodicTimer.new(interval) do
            if @transport.connected?
              check[:issued] = Time.now.to_i
              process_check(check.dup)
            end
          end
        end
      end
    end

    def setup_standalone
      @logger.debug('scheduling standalone checks')
      standard_checks = @settings.checks.select do |check|
        check[:standalone]
      end
      extension_checks = @extensions.checks.select do |check|
        check[:standalone] && check[:interval].is_a?(Integer)
      end
      schedule_checks(standard_checks + extension_checks)
    end

    def setup_sockets
      options = @settings[:client][:socket] || Hash.new
      options[:bind] ||= '127.0.0.1'
      options[:port] ||= 3030
      @logger.debug('binding client tcp and udp sockets', {
        :options => options
      })
      EM::start_server(options[:bind], options[:port], Socket) do |socket|
        socket.logger = @logger
        socket.settings = @settings
        socket.transport = @transport
      end
      EM::open_datagram_socket(options[:bind], options[:port], Socket) do |socket|
        socket.logger = @logger
        socket.settings = @settings
        socket.transport = @transport
        socket.reply = false
      end
    end

    def unsubscribe
      @logger.warn('unsubscribing from client subscriptions')
      @transport.unsubscribe
    end

    def complete_checks_in_progress(&block)
      @logger.info('completing checks in progress', {
        :checks_in_progress => @checks_in_progress
      })
      retry_until_true do
        if @checks_in_progress.empty?
          block.call
          true
        end
      end
    end

    def start
      setup_transport
      setup_keepalives
      setup_subscriptions
      setup_standalone
      setup_sockets
    end

    def stop
      @logger.warn('stopping')
      @timers.each do |timer|
        timer.cancel
      end
      unsubscribe
      complete_checks_in_progress do
        @extensions.stop_all do
          @transport.close
          @logger.warn('stopping reactor')
          EM::stop_event_loop
        end
      end
    end

    def trap_signals
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
  end
end
