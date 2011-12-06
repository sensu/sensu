module Redis
  class Reconnect < Redis::Client
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
        EM.add_timer(1) do
          reconnect(@host, @port)
        end
      else
        until @queue.empty?
          @queue.shift.fail RuntimeError.new 'connection closed'
        end
      end
    end
  end
end
