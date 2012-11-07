gem 'ruby-redis', '0.0.2'

require 'redis'

module Sensu
  class Redis < Redis::Client
    attr_accessor :settings, :on_tcp_connection_failure

    alias :em_reconnect :reconnect

    def initialize(*arguments)
      super
      @logger = Sensu::Logger.get
      @settings = Hash.new
      @connection_established = false
      @connected = false
      @reconnecting = false
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
      @reconnecting = false
      if @settings[:password]
        auth(@settings[:password]).callback do |reply|
          unless reply == 'OK'
            @logger.fatal('redis authentication failed')
            close_connection
          end
        end
      end
      info.callback do |reply|
        redis_version = reply.split(/\n/).select { |v| v =~ /^redis_version/ }.first.split(/:/).last.chomp
        if redis_version < '1.3.14'
          @logger.fatal('redis version must be >= 2.0 RC 1')
          close_connection
        end
      end
      setup_heartbeat
    end

    def reconnect(immediate=false, wait=10)
      if @reconnecting && !immediate
        EM::Timer.new(wait) do
          em_reconnect(@settings[:host], @settings[:port])
        end
      else
        @reconnecting = true
        em_reconnect(@settings[:host], @settings[:port])
      end
    end

    def close
      @closing_connection = true
      close_connection
    end

    def on_tcp_connection_loss(&block)
      if block.respond_to?(:call)
        @on_tcp_connection_loss = block
      end
    end

    def unbind
      @connected = false
      super
      unless @closing_connection
        if @connection_established
          if @on_tcp_connection_loss
            @on_tcp_connection_loss.call(self, @settings)
          end
        else
          if @on_tcp_connection_failure
            @on_tcp_connection_failure.call(self, @settings)
          end
        end
      end
    end

    def connected?
      @connected
    end

    def self.connect(options, additional={})
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
      connection = EM::connect(host, port, self) do |redis|
        redis.settings = {
          :host => host,
          :port => port,
          :password => password
        }
      end
      if additional[:on_tcp_connection_failure].respond_to?(:call)
        connection.on_tcp_connection_failure = additional[:on_tcp_connection_failure]
      end
      connection
    end
  end
end
