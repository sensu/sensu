class Hash
  def symbolize_keys(item=self)
    case item
    when Array
      item.map do |i|
        symbolize_keys(i)
      end
    when Hash
      Hash[
        item.map do |key, value|
          new_key = key.is_a?(String) ? key.to_sym : key
          new_value = symbolize_keys(value)
          [new_key, new_value]
        end
      ]
    else
      item
    end
  end
end

class String
  def self.unique(chars=32)
    rand(36**chars).to_s(36)
  end
end

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
