gem 'amqp', '0.9.10'

require 'amqp'

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
      @connection.on_tcp_connection_loss do |connection, settings|
        unless connection.reconnecting?
          @before_reconnect.call
          connection.periodically_reconnect(5)
        end
      end
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
