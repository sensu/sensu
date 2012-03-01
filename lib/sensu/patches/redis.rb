module Redis
  class Client
    def connection_completed
      @connected = true
      @port, @host = Socket.unpack_sockaddr_in(get_peername)
    end

    def close
      @closing_connection = true
      close_connection_after_writing
    end

    def unbind
      unless !@connected || @closing_connection
        EM::Timer.new(1) do
          reconnect(@host, @port)
        end
      else
        until @queue.empty?
          @queue.shift.fail RuntimeError.new 'connection closed'
        end
        unless @connected
          raise "could not connect to redis"
        end
      end
    end
  end

  def self.connect(options={})
    host = options[:host] || 'localhost'
    port = options[:port] || 6379
    redis = EM::connect(host, port, Redis::Client)
    redis.info do |info|
      redis_version = info.split(/\n/).first.split(/:/).last
      unless redis_version.to_i >= 2
        raise "redis version must be >= 2.0"
      end
    end
    redis
  end
end
