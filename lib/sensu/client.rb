require File.join(File.dirname(__FILE__), 'config')

module Sensu
  class Client
    def self.run(options={})
      client = self.new(options)
      if options[:daemonize]
        Process.daemonize
      end
      if options[:pid_file]
        Process.write_pid(options[:pid_file])
      end
      EM::threadpool_size = 14
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
      config = Sensu::Config.new(options)
      @logger = config.logger
      @settings = config.settings
      @timers = Array.new
      @checks_in_progress = Array.new
    end

    def setup_rabbitmq
      @logger.debug('connecting to rabbitmq', {
        :settings => @settings.rabbitmq.to_hash
      })
      @rabbitmq = AMQP.connect(@settings.rabbitmq.to_hash)
      @amq = AMQP::Channel.new(@rabbitmq)
    end

    def publish_keepalive
      payload = @settings.client.to_hash.merge(:timestamp => Time.now.to_i)
      @logger.debug('publishing keepalive', {
        :payload => payload
      })
      @amq.queue('keepalives').publish(payload.to_json)
    end

    def setup_keepalives
      @logger.debug('scheduling keepalives')
      publish_keepalive
      @timers << EM::PeriodicTimer.new(30) do
        unless @rabbitmq.reconnecting?
          publish_keepalive
        end
      end
    end

    def publish_result(check)
      payload = {
        :client => @settings.client.name,
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
      if @settings.checks.key?(check[:name])
        unless @checks_in_progress.include?(check[:name])
          @logger.debug('executing check', {
            :check => check
          })
          @checks_in_progress.push(check[:name])
          unmatched_tokens = Array.new
          command = @settings.checks[check[:name]].command.gsub(/:::(.*?):::/) do
            token = $1.to_s
            begin
              value = @settings.client.instance_eval(token)
              if value.nil?
                unmatched_tokens.push(token)
              end
            rescue NoMethodError
              value = nil
              unmatched_tokens.push(token)
            end
            value
          end
          if unmatched_tokens.empty?
            execute = proc do
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
            publish = proc do
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
      @settings.client.subscriptions.uniq.each do |exchange|
        @logger.debug('binding queue to exchange', {
          :queue => @uniq_queue_name,
          :exchange => exchange
        })
        @check_request_queue.bind(@amq.fanout(exchange))
      end
      @check_request_queue.subscribe do |payload|
        begin
          check = JSON.parse(payload, :symbolize_names => true)
          if check[:name].is_a?(String) && check[:issued].is_a?(Integer)
            @logger.info('received check request', {
              :check => check
            })
            execute_check(check)
          else
            @logger.warn('invalid check request', {
              :check => check
            })
          end
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
        if @rabbitmq.reconnecting?
          @logger.warn('reconnecting to rabbitmq')
        else
          unless @check_request_queue.subscribed?
            @logger.warn('re-subscribing to client subscriptions')
            setup_subscriptions
          end
        end
      end
    end

    def setup_standalone(options={})
      @logger.debug('scheduling standalone checks')
      standalone_check_count = 0
      @settings.checks.each do |name, details|
        check = details.to_hash.merge(:name => name)
        if check[:standalone]
          standalone_check_count += 1
          stagger = options[:test] ? 0 : 7
          @timers << EM::Timer.new(stagger * standalone_check_count) do
            interval = options[:test] ? 0.5 : check[:interval]
            @timers << EM::PeriodicTimer.new(interval) do
              unless @rabbitmq.reconnecting?
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
      EM::start_server('127.0.0.1', 3030, ClientSocket) do |socket|
        socket.protocol = :tcp
        socket.settings = @settings
        socket.logger = @logger
        socket.amq = @amq
      end
      @logger.debug('binding client udp socket')
      EM::open_datagram_socket('127.0.0.1', 3030, ClientSocket) do |socket|
        socket.protocol = :udp
        socket.settings = @settings
        socket.logger = @logger
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
        EM::PeriodicTimer.new(0.25) do
          EM::stop_event_loop
        end
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
      unless @rabbitmq.reconnecting?
        @logger.warn('unsubscribing from client subscriptions')
        @check_request_queue.unsubscribe do
          stop_reactor
        end
      else
        EM::stop_event_loop
      end
    end
  end

  class ClientSocket < EM::Connection
    attr_accessor :protocol, :settings, :logger, :amq

    def reply(data)
      if @protocol == :tcp
        send_data(data)
      end
    end

    def receive_data(data)
      if data == 'ping'
        @logger.debug('socket received ping')
        reply('pong')
      else
        @logger.debug('socket received data', {
          :data => data
        })
        begin
          check = JSON.parse(data, :symbolize_names => true)
          validates = [:name, :output].all? do |key|
            check[key].is_a?(String)
          end
          check[:issued] ||= Time.now.to_i
          check[:status] ||= 0
          if validates && check[:status].is_a?(Integer)
            payload = {
              :client => @settings.client.name,
              :check => check
            }
            @logger.info('publishing check result', {
              :payload => payload
            })
            @amq.queue('results').publish(payload.to_json)
            reply('ok')
          else
            @logger.warn('invalid check result', {
              :check => check
            })
            reply('invalid')
          end
        rescue JSON::ParserError => error
          @logger.warn('check result must be valid json', {
            :data => data,
            :error => error.to_s
          })
          reply('invalid')
        end
      end
    end
  end
end
