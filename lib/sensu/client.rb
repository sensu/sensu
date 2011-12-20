require File.join(File.dirname(__FILE__), 'config')

module Sensu
  class Client
    def self.run(options={})
      EM.run do
        client = self.new(options)
        client.setup_amqp
        client.setup_keepalives
        client.setup_subscriptions
        client.setup_queue_monitor
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
      @settings = config.settings
      @logger = config.open_log
    end

    def stop(signal)
      @logger.warn('[process] -- ' + signal + ' -- stopping sensu client')
      EM.add_timer(1) do
        EM.stop
      end
    end

    def setup_amqp
      @logger.debug('[amqp] -- connecting to rabbitmq')
      rabbitmq = AMQP.connect(@settings.rabbitmq.to_hash.symbolize_keys)
      @amq = AMQP::Channel.new(rabbitmq)
    end

    def publish_keepalive
      @logger.debug('[keepalive] -- publishing keepalive -- ' + @settings.client.timestamp.to_s)
      @keepalive_queue ||= @amq.queue('keepalives')
      @keepalive_queue.publish(@settings.client.to_json)
    end

    def setup_keepalives
      @logger.debug('[keepalive] -- setup keepalives')
      @settings.client.timestamp = Time.now.to_i
      publish_keepalive
      EM.add_periodic_timer(30) do
        @settings.client.timestamp = Time.now.to_i
        publish_keepalive
      end
    end

    def publish_result(check)
      @logger.info('[result] -- publishing check result -- ' + check.status.to_s + ' -- ' + check.name)
      @result_queue ||= @amq.queue('results')
      @result_queue.publish({
        :client => @settings.client.name,
        :check => check.to_hash
      }.to_json)
    end

    def execute_check(check)
      @logger.debug('[execute] -- executing check -- ' + check.name)
      @checks_in_progress ||= Array.new
      if @settings.checks.key?(check.name)
        unless @checks_in_progress.include?(check.name)
          @checks_in_progress.push(check.name)
          unmatched_tokens = Array.new
          command = @settings.checks[check.name].command.gsub(/:::(.*?):::/) do
            key = $1.to_s
            unmatched_tokens.push(key) unless @settings.client.key?(key)
            @settings.client[key].to_s
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
            EM.defer(execute, publish)
          else
            @logger.warn('[execute] -- missing client attributes -- ' + unmatched_tokens.join(', ') + ' -- ' + check.name)
            check.status = 3
            check.output = 'Missing client attributes: ' + unmatched_tokens.join(', ')
            check.handle = false
            publish_result(check)
            @checks_in_progress.delete(check.name)
          end
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
      @check_queue = @amq.queue(String.unique, :exclusive => true)
      @settings.client.subscriptions.push('uchiwa').uniq!
      @settings.client.subscriptions.each do |exchange|
        @logger.debug('[subscribe] -- queue binding to exchange -- ' + exchange)
        @check_queue.bind(@amq.fanout(exchange))
      end
      @check_queue.subscribe do |check_json|
        check = Hashie::Mash.new(JSON.parse(check_json))
        @logger.info('[subscribe] -- received check -- ' + check.name)
        if check.key?('matching')
          @logger.info('[subscribe] -- check requires matching -- ' + check.name)
          matches = check.matching.all? do |key, value|
            desired = case key
            when /^!/
              key = key.slice(1..-1)
              false
            else
              true
            end
            matched = case key
            when 'subscribes'
              value.all? do |subscription|
                @settings.client.subscriptions.include?(subscription)
              end
            else
              @settings.client[key] == value
            end
            desired == matched
          end
          if matches
            @logger.info('[subscribe] -- client matches -- ' + check.name)
            execute_check(check)
          else
            @logger.info('[subscribe] -- client does not match -- ' + check.name)
          end
        else
          execute_check(check)
        end
      end
    end

    def setup_queue_monitor
      @logger.debug('[monitor] -- setup queue monitor')
      EM.add_periodic_timer(5) do
        unless @check_queue.subscribed?
          @logger.warn('[monitor] -- reconnecting to rabbitmq')
          @check_queue.delete
          EM.add_timer(1) do
            setup_subscriptions
          end
        end
      end
    end

    def setup_socket
      @logger.debug('[socket] -- starting up socket server')
      EM.start_server('127.0.0.1', 3030, ClientSocket) do |socket|
        socket.logger = @logger
        socket.client_name = @settings.client.name
        socket.result_queue = @amq.queue('results')
      end
    end
  end

  class ClientSocket < EM::Connection
    attr_accessor :logger, :client_name, :result_queue

    def receive_data(data)
      @logger.debug('[socket] -- received data from client')
      begin
        check = Hashie::Mash.new(JSON.parse(data))
        validates = %w[name status output].all? do |key|
          check.key?(key)
        end
        if validates
          @logger.info('[socket] -- publishing check result -- ' + check.name)
          @result_queue.publish({
            :client => @client_name,
            :check => check.to_hash
          }.to_json)
        else
          @logger.warn('[socket] -- a check name, exit status, and output are required -- e.g. {name: x, status: 0, output: "y"}')
        end
      rescue JSON::ParserError => error
        @logger.warn('[socket] -- check result must be valid JSON: ' + error)
      end
      close_connection
    end

    def unbind
      @logger.debug('[socket] -- client disconnected')
    end
  end
end
