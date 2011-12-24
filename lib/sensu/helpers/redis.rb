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
      end
    end
  end

  def self.connect(options={})
    host = options[:host] || 'localhost'
    port = options[:port] || 6379
    EM::connect(host, port, Redis::Client)
  end
end
