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
      EM::threadpool_size = 16
      EM::run do
        client.setup_amqp
        client.setup_keepalives
        client.setup_subscriptions
        client.setup_queue_monitor
        client.setup_standalone
        client.setup_socket

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

    def setup_amqp
      @logger.debug('[amqp] -- connecting to rabbitmq')
      rabbitmq = AMQP.connect(@settings.rabbitmq.to_hash.symbolize_keys)
      @amq = AMQP::Channel.new(rabbitmq)
    end

    def publish_keepalive
      @settings.client.timestamp = Time.now.to_i
      @logger.debug('[keepalive] -- publishing keepalive -- ' + @settings.client.timestamp.to_s)
      @amq.queue('keepalives').publish(@settings.client.to_json)
    end

    def setup_keepalives
      @logger.debug('[keepalive] -- setup keepalives')
      publish_keepalive
      @timers << EM::PeriodicTimer.new(30) do
        publish_keepalive
      end
    end

    def publish_result(check)
      @logger.info('[result] -- publishing check result -- ' + [check.name, check.status, check.output].join(' -- '))
      @amq.queue('results').publish({
        :client => @settings.client.name,
        :check => check.to_hash
      }.to_json)
    end

    def execute_check(check)
      @logger.debug('[execute] -- attempting to execute check -- ' + check.name)
      if @settings.checks.key?(check.name)
        unless @checks_in_progress.include?(check.name)
          @logger.debug('[execute] -- executing check -- ' + check.name)
          @checks_in_progress.push(check.name)
          unmatched_tokens = Array.new
          command = @settings.checks[check.name].command.gsub(/:::(.*?):::/) do
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
              Bundler.with_clean_env do
                IO.popen(command + ' 2>&1') do |io|
                  check.output = io.read
                end
              end
              check.status = $?.exitstatus
            end
            publish = proc do
              unless check.status.nil?
                publish_result(check)
              else
                @logger.warn('[execute] -- nil exit status code -- ' + check.name)
              end
              @checks_in_progress.delete(check.name)
            end
            EM::defer(execute, publish)
          else
            @logger.warn('[execute] -- missing client attributes -- ' + unmatched_tokens.join(', ') + ' -- ' + check.name)
            check.status = 3
            check.output = 'Missing client attributes: ' + unmatched_tokens.join(', ')
            check.handle = false
            publish_result(check)
            @checks_in_progress.delete(check.name)
          end
        else
          @logger.debug('[execute] -- previous check execution still in progress -- ' + check.name)
        end
      else
        @logger.warn('[execute] -- unkown check -- ' + check.name)
        check.status = 3
        check.output = 'Unknown check'
        check.handle = false
        publish_result(check)
        @checks_in_progress.delete(check.name)
      end
    end

    def setup_subscriptions
      @logger.debug('[subscribe] -- setup subscriptions')
      @check_request_queue = @amq.queue(String.unique, :exclusive => true)
      @settings.client.subscriptions.uniq.each do |exchange|
        @logger.debug('[subscribe] -- queue binding to exchange -- ' + exchange)
        @check_request_queue.bind(@amq.fanout(exchange))
      end
      @check_request_queue.subscribe do |check_request_json|
        check = Hashie::Mash.new(JSON.parse(check_request_json))
        @logger.info('[subscribe] -- received check request -- ' + check.name)
        execute_check(check)
      end
    end

    def setup_queue_monitor
      @logger.debug('[monitor] -- setup queue monitor')
      @timers << EM::PeriodicTimer.new(5) do
        unless @check_request_queue.subscribed?
          @logger.warn('[monitor] -- re-subscribing to subscriptions')
          @check_request_queue.delete
          @timers << EM::Timer.new(1) do
            setup_subscriptions
          end
        end
      end
    end

    def setup_standalone(options={})
      @logger.debug('[standalone] -- setup standalone')
      standalone_check_count = 0
      @settings.checks.each do |name, details|
        if details.standalone
          standalone_check_count += 1
          check = Hashie::Mash.new(details.merge(:name => name))
          stagger = options[:test] ? 0 : 7
          @timers << EM::Timer.new(stagger*standalone_check_count) do
            interval = options[:test] ? 0.5 : details.interval
            @timers << EM::PeriodicTimer.new(interval) do
              check.issued = Time.now.to_i
              execute_check(check)
            end
          end
        end
      end
    end

    def setup_socket
      @logger.debug('[socket] -- starting up socket')
      EM::start_server('127.0.0.1', 3030, ClientSocket) do |socket|
        socket.settings = @settings
        socket.logger = @logger
        socket.amq = @amq
      end
    end

    def stop_reactor
      @logger.info('[stop] -- completing checks in progress')
      complete_in_progress = EM::tick_loop do
        if @checks_in_progress.empty?
          :stop
        end
      end
      complete_in_progress.on_stop do
        @logger.warn('[stop] -- stopping reactor')
        EM::PeriodicTimer.new(0.25) do
          EM::stop_event_loop
        end
      end
    end

    def stop(signal)
      @logger.warn('[stop] -- stopping sensu client -- ' + signal)
      @timers.each do |timer|
        timer.cancel
      end
      @logger.warn('[stop] -- unsubscribing from subscriptions')
      @check_request_queue.unsubscribe do
        stop_reactor
      end
    end
  end

  class ClientSocket < EM::Connection
    attr_accessor :settings, :logger, :amq

    def receive_data(data)
      if data == 'ping'
        @logger.debug('[socket] -- received ping')
        send_data('pong')
      else
        @logger.debug('[socket] -- received data -- ' + data)
        begin
          check = Hashie::Mash.new(JSON.parse(data))
          validates = %w[name output].all? do |key|
            check[key].is_a?(String)
          end
          check.status ||= 0
          if validates && check.status.is_a?(Integer)
            @logger.info('[socket] -- publishing check result -- ' + [check.name, check.status, check.output].join(' -- '))
            @amq.queue('results').publish({
              :client => @settings.client.name,
              :check => check.to_hash
            }.to_json)
            send_data('ok')
          else
            @logger.warn('[socket] -- check name and output must be strings, status defaults to 0 -- e.g. {"name": "x", "output": "y"}')
            send_data('invalid')
          end
        rescue JSON::ParserError => error
          @logger.warn('[socket] -- check result must be valid JSON: ' + error.to_s)
          send_data('invalid')
        end
      end
    end
  end
end
