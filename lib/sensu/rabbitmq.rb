gem 'amqp', '1.0.0'

require 'amqp'

module AMQ
  module Client
    module Async
      module Adapter
        def send_heartbeat
          if tcp_connection_established? && !reconnecting?
            if !@handling_skipped_hearbeats && @last_server_heartbeat
              send_frame(Protocol::HeartbeatFrame)
              if @last_server_heartbeat < (Time.now - (self.heartbeat_interval * 2))
                logger.error('detected missing amqp heartbeats')
                self.handle_skipped_hearbeats
              end
            end
          end
        end
      end
    end
  end
end

module Sensu
  class RabbitMQError < StandardError; end

  class RabbitMQ
    attr_reader :channel

    def initialize
      @on_error = Proc.new {}
      @before_reconnect = Proc.new {}
      @after_reconnect = Proc.new {}
    end

    def on_error(&block)
      @on_error = block
    end

    def before_reconnect(&block)
      @before_reconnect = block
    end

    def after_reconnect(&block)
      @after_reconnect = block
    end

    def connect(options={})
      on_failure = Proc.new do
        error = RabbitMQError.new('cannot connect to rabbitmq')
        @on_error.call(error)
      end
      @connection = AMQP.connect(options, {
        :on_tcp_connection_failure => on_failure,
        :on_possible_authentication_failure => on_failure
      })
      @connection.logger = Logger.get
      reconnect = Proc.new do
        unless @connection.reconnecting?
          @before_reconnect.call
          @connection.periodically_reconnect(5)
        end
      end
      @connection.on_tcp_connection_loss(&reconnect)
      @connection.on_skipped_heartbeats(&reconnect)
      @channel = AMQP::Channel.new(@connection)
      @channel.auto_recovery = true
      @channel.on_error do |channel, channel_close|
        error = RabbitMQError.new('rabbitmq channel closed')
        @on_error.call(error)
      end
      @channel.on_recovery do
        @after_reconnect.call
      end
    end

    def connected?
      @connection.connected?
    end

    def close
      @connection.close
    end

    def self.connect(options={})
      options ||= Hash.new
      rabbitmq = self.new
      rabbitmq.connect(options)
      rabbitmq
    end
  end
end
