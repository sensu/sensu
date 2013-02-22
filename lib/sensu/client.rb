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
      base.setup_process
      @timers = Array.new
      @checks_in_progress = Array.new
      @safe_mode = @settings[:client][:safe_mode] || false
    end

    def setup_rabbitmq
      @logger.debug('connecting to rabbitmq', {
        :settings => @settings[:rabbitmq]
      })
      @rabbitmq = RabbitMQ.connect(@settings[:rabbitmq])
      @rabbitmq.on_error do |error|
        @logger.fatal('rabbitmq connection error', {
          :error => error.to_s
        })
        stop
      end
      @rabbitmq.before_reconnect do
        @logger.warn('reconnecting to rabbitmq')
      end
      @rabbitmq.after_reconnect do
        @logger.info('reconnected to rabbitmq')
      end
      @amq = @rabbitmq.channel
    end

    def publish_keepalive
      payload = @settings[:client].merge(:timestamp => Time.now.to_i)
      @logger.debug('publishing keepalive', {
        :payload => payload
      })
      @amq.direct('keepalives').publish(payload.to_json)
    end

    def setup_keepalives
      @logger.debug('scheduling keepalives')
      publish_keepalive
      @timers << EM::PeriodicTimer.new(20) do
        if @rabbitmq.connected?
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
      @amq.direct('results').publish(payload.to_json)
    end

    def execute_check(check)
      @logger.debug('attempting to execute check', {
        :check => check
      })
      unless @checks_in_progress.include?(check[:name])
        @logger.debug('executing check', {
          :check => check
        })
        @checks_in_progress.push(check[:name])
        unmatched_tokens = Array.new
        command = check[:command].gsub(/:::(.*?):::/) do
          token = $1.to_s
          matched = token.split('.').inject(@settings[:client]) do |client, attribute|
            client[attribute].nil? ? break : client[attribute]
          end
          if matched.nil?
            unmatched_tokens.push(token)
          end
          matched
        end
        if unmatched_tokens.empty?
          execute = Proc.new do
            started = Time.now.to_f
            begin
              check[:output], check[:status] = IO.popen(command, 'r', check[:timeout])
            rescue => error
              @logger.warn('unexpected error', {
                :error => error.to_s
              })
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
          @logger.warn('missing client attributes', {
            :check => check,
            :unmatched_tokens => unmatched_tokens
          })
          check[:output] = 'Missing client attributes: ' + unmatched_tokens.join(', ')
          check[:status] = 3
          check[:handle] = false
          publish_result(check)
          @checks_in_progress.delete(check[:name])
        end
      else
        @logger.warn('previous check execution in progress', {
          :check => check
        })
      end
    end

    def setup_subscriptions
      @logger.debug('subscribing to client subscriptions')
      @check_request_queue = @amq.queue('', :auto_delete => true) do |queue|
        @settings[:client][:subscriptions].uniq.each do |exchange_name|
          @logger.debug('binding queue to exchange', {
            :queue => {
              :name => queue.name
            },
            :exchange => {
              :name => exchange_name
            }
          })
          queue.bind(@amq.fanout(exchange_name))
        end
        queue.subscribe do |payload|
          begin
            check = JSON.parse(payload, :symbolize_names => true)
            @logger.info('received check request', {
              :check => check
            })
            if @settings.check_exists?(check[:name])
              check.merge!(@settings[:checks][check[:name]])
              execute_check(check)
            elsif @safe_mode
              @logger.warn('check is not defined', {
                :check => check
              })
              check[:output] = 'Check is not defined (safe mode)'
              check[:status] = 3
              check[:handle] = false
              publish_result(check)
            else
              execute_check(check)
            end
          rescue JSON::ParserError => error
            @logger.warn('check request payload must be valid json', {
              :payload => payload,
              :error => error.to_s
            })
          end
        end
      end
    end

    def setup_standalone
      @logger.debug('scheduling standalone checks')
      standalone_check_count = 0
      stagger = testing? ? 0 : 2
      @settings.checks.each do |check|
        if check[:standalone]
          standalone_check_count += 1
          scheduling_delay = stagger * standalone_check_count % 30
          @timers << EM::Timer.new(scheduling_delay) do
            interval = testing? ? 0.5 : check[:interval]
            @timers << EM::PeriodicTimer.new(interval) do
              if @rabbitmq.connected?
                check[:issued] = Time.now.to_i
                execute_check(check)
              end
            end
          end
        end
      end
    end

    def setup_sockets
      @logger.debug('binding client tcp socket')
      EM::start_server('127.0.0.1', 3030, Socket) do |socket|
        socket.protocol = :tcp
        socket.logger = @logger
        socket.settings = @settings
        socket.amq = @amq
      end
      @logger.debug('binding client udp socket')
      EM::open_datagram_socket('127.0.0.1', 3030, Socket) do |socket|
        socket.protocol = :udp
        socket.logger = @logger
        socket.settings = @settings
        socket.amq = @amq
      end
    end

    def unsubscribe(&block)
      @logger.warn('unsubscribing from client subscriptions')
      @check_request_queue.unsubscribe
      block.call
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
      setup_rabbitmq
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
      unsubscribe do
        complete_checks_in_progress do
          @rabbitmq.close
          @logger.warn('stopping reactor')
          EM::stop_event_loop
        end
      end
    end

    def trap_signals
      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          @logger.warn('received signal', {
            :signal => signal
          })
          stop
        end
      end
    end
  end
end
