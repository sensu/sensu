module Redis
  class Client
    attr_accessor :redis_host, :redis_port, :redis_password

    def connection_completed
      @connected = true
      @reconnecting = false
      if @redis_password
        auth(@redis_password).callback do |reply|
          unless reply == 'OK'
            raise('could not authenticate')
          end
        end
      end
      info.callback do |reply|
        redis_version = reply.split(/\n/).first.split(/:/).last.chomp
        if redis_version < '1.3.14'
          raise('redis version must be >= 2.0 RC 1')
        end
      end
    end

    def close
      @closing_connection = true
      close_connection_after_writing
    end

    def unbind
      unless !@connected || @closing_connection
        EM::Timer.new(1) do
          @reconnecting = true
          reconnect(@redis_host, @redis_port)
        end
      else
        until @queue.empty?
          @queue.shift.fail RuntimeError.new('connection closed')
        end
        unless @connected
          raise('could not connect to redis')
        end
      end
    end

    def reconnecting?
      @reconnecting || false
    end
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
        raise('invalid redis url')
      end
    else
      host = options[:host] || 'localhost'
      port = options[:port] || 6379
      password = options[:password]
    end
    EM::connect(host, port, Redis::Client) do |client|
      client.redis_host = host
      client.redis_port = port
      client.redis_password = password
    end
  end
end
