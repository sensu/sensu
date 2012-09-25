class TestSensuClientSocket < TestCase
  def test_client_sockets
    server, client = base_server_client
    client.setup_sockets
    EM::Timer.new(1) do
      EM::connect('127.0.0.1', 3030, nil) do |socket|
        socket.send_data('{"name": "tcp_socket", "output": "tcp", "status": 1}')
        socket.close_connection_after_writing
      end
      EM::open_datagram_socket('127.0.0.1', 0, nil) do |socket|
        data = '{"name": "udp_socket", "output": "udp", "status": 1}'
        2.times do
          socket.send_datagram(data, '127.0.0.1', 3030)
        end
        socket.close_connection_after_writing
      end
    end
    EM::Timer.new(3) do
      server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
        assert(events.include?('tcp_socket'))
        assert(events.include?('udp_socket'))
        done
      end
    end
  end
end
