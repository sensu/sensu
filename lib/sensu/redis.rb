require 'redis'

module Sensu
  class Redis < Redis::Client
    attr_accessor :host, :port, :password, :on_disconnect

    def initialize(*arguments)
      super
      @logger = Cabin::Channel.get
      @connection_established = false
      @connected = false
      @closing_connection = false
    end

    def setup_heartbeat
      @heartbeat ||= EM::PeriodicTimer.new(10) do
        if connected?
          ping
        end
      end
    end

    def connection_completed
      @connection_established = true
      @connected = true
      if @password
        auth(@password).callback do |reply|
          unless reply == 'OK'
            @logger.fatal('redis authentication failed')
            close_connection
          end
        end
      end
      info.callback do |reply|
        redis_version = reply.split(/\n/).first.split(/:/).last.chomp
        if redis_version < '1.3.14'
          @logger.fatal('redis version must be >= 2.0 RC 1')
          close_connection
        end
      end
      setup_heartbeat
    end

    def reconnect!
      EM::Timer.new(1) do
        reconnect(@host, @port)
      end
    end

    def close
      @closing_connection = true
      close_connection
    end

    def unbind
      @connected = false
      super
      if @on_disconnect && !@closing_connection
        @on_disconnect.call
      end
    end

    def connection_established?
      @connection_established
    end

    def connected?
      @connected
    end

    def self.connect(options)
      options ||= Hash.new
      if options.is_a?(String)
        begin
          uri = URI.parse(options)
          host = uri.host
          port = uri.port || 6379
          password = uri.password
        rescue
          @logger.fatal('invalid redis url')
          @logger.fatal('SENSU NOT RUNNING!')
          exit 2
        end
      else
        host = options[:host] || 'localhost'
        port = options[:port] || 6379
        password = options[:password]
      end
      EM::connect(host, port, self) do |redis|
        redis.host = host
        redis.port = port
        redis.password = password
      end
    end
  end
end
