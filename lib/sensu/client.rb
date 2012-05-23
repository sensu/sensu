require File.join(File.dirname(__FILE__), 'base')
require File.join(File.dirname(__FILE__), 'socket')

module Sensu
  class Client
    def self.run(options={})
      client = self.new(options)
      EM::run do
        client.setup_rabbitmq
        client.setup_keepalives
        client.setup_subscriptions
        client.setup_rabbitmq_monitor
        client.setup_standalone
        client.setup_sockets

        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            client.stop(signal)
          end
        end
      end
    end

    def initialize(options={})
      base = Sensu::Base.new(options)
      @logger = base.logger
      @settings = base.settings
      @timers = Array.new
      @checks_in_progress = Array.new
    end

    def setup_rabbitmq
      @logger.debug('connecting to rabbitmq', {
        :settings => @settings[:rabbitmq]
      })
      @rabbitmq = AMQP.connect(@settings[:rabbitmq])
      @amq = AMQP::Channel.new(@rabbitmq)
    end

    def publish_keepalive
      payload = @settings[:client].merge(:timestamp => Time.now.to_i)
      @logger.debug('publishing keepalive', {
        :payload => payload
      })
      @amq.queue('keepalives').publish(payload.to_json)
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
      @amq.queue('results').publish(payload.to_json)
    end

    def execute_check(check)
      @logger.debug('attempting to execute check', {
        :check => check
      })
      if @settings.check_exists?(check[:name])
        unless @checks_in_progress.include?(check[:name])
          @logger.debug('executing check', {
            :check => check
          })
          @checks_in_progress.push(check[:name])
          unmatched_tokens = Array.new
          command = @settings[:checks][check[:name]][:command].gsub(/:::(.*?):::/) do
            token = $1.to_s
            begin
              substitute = @settings[:client].instance_eval(token)
            rescue NameError, NoMethodError
              substitute = nil
            end
            if substitute.nil?
              unmatched_tokens.push(token)
            end
            substitute
          end
          if unmatched_tokens.empty?
            execute = Proc.new do
              started = Time.now.to_f
              begin
                IO.popen(command + ' 2>&1') do |io|
                  check[:output] = io.read
                end
                check[:status] = $?.exitstatus
              rescue => error
                @logger.warn('unexpected error', {
                  :error => error.to_s
                })
                check[:output] = 'Unexpected error: ' + error.to_s
                check[:status] = 2
              end
              check[:duration] = ('%.3f' % (Time.now.to_f - started)).to_f
            end
            publish = Proc.new do
              unless check[:status].nil?
                publish_result(check)
              else
                @logger.warn('nil exit status code', {
                  :check => check
                })
              end
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
      else
        @logger.warn('unknown check', {
          :check => check
        })
        check[:output] = 'Unknown check'
        check[:status] = 3
        check[:handle] = false
        publish_result(check)
        @checks_in_progress.delete(check[:name])
      end
    end

    def setup_subscriptions
      @logger.debug('subscribing to client subscriptions')
      @uniq_queue_name ||= rand(36 ** 32).to_s(36)
      @check_request_queue = @amq.queue(@uniq_queue_name, :auto_delete => true)
      @settings[:client][:subscriptions].uniq.each do |exchange_name|
        @logger.debug('binding queue to exchange', {
          :queue => @uniq_queue_name,
          :exchange => {
            :name => exchange_name,
            :type => 'fanout'
          }
        })
        @check_request_queue.bind(@amq.fanout(exchange_name))
      end
      @check_request_queue.subscribe do |payload|
        begin
          check = JSON.parse(payload, :symbolize_names => true)
          @logger.info('received check request', {
            :check => check
          })
          execute_check(check)
        rescue JSON::ParserError => error
          @logger.warn('check request payload must be valid json', {
            :payload => payload,
            :error => error.to_s
          })
        end
      end
    end

    def setup_rabbitmq_monitor
      @logger.debug('monitoring rabbitmq connection')
      @timers << EM::PeriodicTimer.new(5) do
        if @rabbitmq.connected?
          unless @check_request_queue.subscribed?
            @logger.warn('re-subscribing to client subscriptions')
            setup_subscriptions
          end
        else
          @logger.warn('reconnecting to rabbitmq')
        end
      end
    end

    def setup_standalone
      @logger.debug('scheduling standalone checks')
      standalone_check_count = 0
      stagger = testing? ? 0 : 7
      @settings.checks.each do |check|
        if check[:standalone]
          standalone_check_count += 1
          @timers << EM::Timer.new(stagger * standalone_check_count) do
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
      EM::start_server('127.0.0.1', 3030, Sensu::Socket) do |socket|
        socket.protocol = :tcp
        socket.logger = @logger
        socket.settings = @settings
        socket.amq = @amq
      end
      @logger.debug('binding client udp socket')
      EM::open_datagram_socket('127.0.0.1', 3030, Sensu::Socket) do |socket|
        socket.protocol = :udp
        socket.logger = @logger
        socket.settings = @settings
        socket.amq = @amq
      end
    end

    def stop_reactor
      @logger.info('completing checks in progress', {
        :checks_in_progress => @checks_in_progress
      })
      complete_in_progress = EM::tick_loop do
        if @checks_in_progress.empty?
          :stop
        end
      end
      complete_in_progress.on_stop do
        @logger.warn('stopping reactor')
        EM::stop_event_loop
      end
    end

    def stop(signal)
      @logger.warn('received signal', {
        :signal => signal
      })
      @logger.warn('stopping')
      @timers.each do |timer|
        timer.cancel
      end
      if @rabbitmq.connected?
        @logger.warn('unsubscribing from client subscriptions')
        @check_request_queue.unsubscribe do
          stop_reactor
        end
      else
        EM::stop_event_loop
      end
    end

    private

    def testing?
      File.basename($0) == 'rake'
    end
  end
end
