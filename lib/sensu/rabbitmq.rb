gem 'amqp', '0.9.7'

require 'amqp'

module Sensu
  class RabbitMQ
    attr_reader :channel

    attr_accessor :on_failure, :on_reconnect, :on_channel_error

    def initialize
      @logger = Logger.get
      @on_failure = Proc.new {}
      @on_reconnect = Proc.new do |connection, settings|
        connection.periodically_reconnect(5)
      end
      @on_channel_error = Proc.new do
        @logger.fatal('SENSU NOT RUNNING!')
        exit 2
      end
    end

    def connect(options={})
      heartbeat = options.reject! do |key, value|
        key == :heartbeat
      end
      if heartbeat
        @logger.warn('rabbitmq heartbeats are disabled')
      end
      @logger.debug('connecting to rabbitmq', {
        :settings => options
      })
      connection_failure = Proc.new do
        @logger.fatal('cannot connect to rabbitmq', {
          :settings => options
        })
        @logger.fatal('SENSU NOT RUNNING!')
        @on_failure.call
        exit 2
      end
      @connection = AMQP.connect(options, {
        :on_tcp_connection_failure => connection_failure,
        :on_possible_authentication_failure => connection_failure
      })
      @connection.logger = NullLogger.get
      @connection.on_tcp_connection_loss do |connection, settings|
        unless connection.reconnecting?
          @logger.warn('reconnecting to rabbitmq')
          @on_reconnect.call(connection, settings)
        end
      end
      @channel = AMQP::Channel.new(@connection)
      @channel.auto_recovery = true
      @channel.on_error do |channel, channel_close|
        @logger.fatal('rabbitmq channel closed', {
          :error => {
            :reply_code => channel_close.reply_code,
            :reply_text => channel_close.reply_text
          }
        })
        @on_channel_error.call(channel, channel_close)
      end
    end

    def close
      @connection.close
    end

    def connected?
      @connection.connected?
    end
  end
end
