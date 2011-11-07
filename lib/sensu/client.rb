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
            EM.warning('[process] -- ' + signal + ' -- stopping sensu client')
            EM.add_timer(1) do
              EM.stop
            end
          end
        end
      end
    end

    def initialize(options={})
      config = Sensu::Config.new(options)
      @settings = config.settings
      EM.syslog_setup(@settings.syslog.host, @settings.syslog.port)
    end

    def setup_amqp
      EM.debug("[amqp] -- connecting to rabbitmq")
      connection = AMQP.connect(@settings.rabbitmq.to_hash.symbolize_keys)
      @amq = MQ.new(connection)
    end

    def publish_keepalive
      EM.debug('[keepalive] -- publishing keepalive -- ' + @settings.client.timestamp.to_s)
      @keepalive_queue ||= @amq.queue('keepalives')
      @keepalive_queue.publish(@settings.client.to_json)
    end

    def setup_keepalives
      @settings.client.timestamp = Time.now.to_i
      publish_keepalive
      EM.add_periodic_timer(30) do
        @settings.client.timestamp = Time.now.to_i
        publish_keepalive
      end
    end

    def publish_result(check)
      EM.info('[result] -- publishing check result -- ' + check.name)
      @result_queue ||= @amq.queue('results')
      @result_queue.publish({
        :client => @settings.client.name,
        :check => check.to_hash
      }.to_json)
    end

    def execute_check(check)
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
              IO.popen(command + ' 2>&1') do |io|
                check.output = io.read
              end
              check.status = $?.exitstatus
            end
            publish = proc do |result|
              publish_result(check)
              @checks_in_progress.delete(check.name)
            end
            EM.defer(execute, publish)
          else
            EM.warning('[execute] -- missing client attributes -- ' + unmatched_tokens.join(', ') + ' -- ' + check.name)
            check.status = 3
            check.output = 'Missing client attributes: ' + unmatched_tokens.join(', ')
            check.internal = true
            publish_result(check)
            @checks_in_progress.delete(check.name)
          end
        end
      else
        EM.warning('[execute] -- unkown check -- ' + check.name)
        check.status = 3
        check.output = 'Unknown check'
        check.internal = true
        publish_result(check)
        @checks_in_progress.delete(check.name)
      end
    end

    def setup_subscriptions
      @check_queue = @amq.queue(UUIDTools::UUID.random_create.to_s, :exclusive => true)
      @settings.client.subscriptions.each do |exchange|
        EM.debug('[subscribe] -- queue binding to exchange -- ' + exchange)
        @check_queue.bind(@amq.fanout(exchange))
      end
      @check_queue.subscribe do |check_json|
        check = Hashie::Mash.new(JSON.parse(check_json))
        EM.info('[subscribe] -- received check -- ' + check.name)
        execute_check(check)
      end
    end

    def setup_queue_monitor
      EM.add_periodic_timer(5) do
        unless @check_queue.subscribed?
          EM.warning('[monitor] -- reconnecting to rabbitmq')
          @check_queue.delete
          EM.add_timer(1) do
            setup_subscriptions
          end
        end
      end
    end

    def setup_socket
      EM.debug('[socket] -- starting up socket server')
      EM.start_server('127.0.0.1', 3030, ClientSocket) do |socket|
        socket.client_name = @settings.client.name
        socket.result_queue = @amq.queue('results')
      end
    end
  end

  class ClientSocket < EM::Connection
    attr_accessor :client_name, :result_queue

    def post_init
      EM.debug('[socket] -- client connected')
    end

    def receive_data(data)
      begin
        check = Hashie::Mash.new(JSON.parse(data))
        validates = %w[name status output].all? do |key|
          check.key?(key)
        end
        if validates
          EM.info('[socket] -- publishing check result -- ' + check.name)
          @result_queue.publish({
            :client => @client_name,
            :check => check.to_hash
          }.to_json)
        else
          EM.warning('[socket] -- a check name, exit status, and output are required -- e.g. {name: x, status: 0, output: "y"}')
        end
      rescue JSON::ParserError
        EM.warning('[socket] -- could not parse check result -- expecting JSON')
      end
      close_connection
    end

    def unbind
      EM.debug('[socket] -- client disconnected')
    end
  end
end
