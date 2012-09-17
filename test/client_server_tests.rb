class TestSensuClientServer < TestCase
  def setup
    @options = {
      :config_file => File.join(File.dirname(__FILE__), 'config.json'),
      :config_dir => File.join(File.dirname(__FILE__), 'conf.d'),
      :log_level => :error
    }
    base = Sensu::Base.new(@options)
    @settings = base.settings
  end

  def bootstrap
    server = Sensu::Server.new(@options)
    client = Sensu::Client.new(@options)
    server.setup_redis
    server.redis.flushall
    server.setup_rabbitmq
    server.setup_keepalives
    server.setup_results
    client.setup_rabbitmq
    client.setup_keepalives
    client.setup_subscriptions
    [server, client]
  end

  def example_event(check_options={})
    event = {
      :client => @settings[:client].sanitize_keys,
      :check => {
        :name => 'example',
        :issued => Time.now.to_i,
        :output => 'WARNING',
        :status => 1,
        :history => [1]
      },
      :occurrences => 1,
      :action => 'create'
    }
    event[:check].merge!(check_options)
    event
  end

  def test_keepalives
    server, client = bootstrap
    EM::Timer.new(1) do
      server.redis.get('client:' + @settings[:client][:name]).callback do |client_json|
        client_attributes = JSON.parse(client_json, :symbolize_names => true).sanitize_keys
        assert_equal(@settings[:client], client_attributes)
        done
      end
    end
  end

  def test_pipe_handler
    server = Sensu::Server.new(@options)
    event = example_event(:handler => 'file')
    server.handle_event(event)
    EM::Timer.new(2) do
      assert(File.exists?('/tmp/sensu_example'))
      output_file = File.open('/tmp/sensu_example', 'r')
      output = JSON.parse(output_file.read, :symbolize_names => true)
      assert_equal(event, output)
      done
    end
  end

  def test_tcp_handler
    server = Sensu::Server.new(@options)
    event = example_event(:handler => 'tcp_socket')
    socket = Proc.new do
      tcp_server = TCPServer.open(1234)
      data = tcp_server.accept.gets
      tcp_server.close
      data
    end
    callback = Proc.new do |data|
      output = JSON.parse(data, :symbolize_names => true)
      assert_equal(event, output)
      done
    end
    EM::Timer.new(2) do
      server.handle_event(event)
    end
    EM::defer(socket, callback)
  end

  def test_udp_handler
    server = Sensu::Server.new(@options)
    event = example_event(:handler => 'udp_socket')
    socket = Proc.new do
      udp_socket = UDPSocket.new
      udp_socket.bind('127.0.0.1', 1234)
      data = udp_socket.recv(1024)
      udp_socket.close
      data
    end
    callback = Proc.new do |data|
      output = JSON.parse(data, :symbolize_names => true)
      assert_equal(event, output)
      done
    end
    EM::Timer.new(2) do
      server.handle_event(event)
    end
    EM::defer(socket, callback)
  end

  def test_publish_subscribe
    server, client = bootstrap
    client.setup_standalone
    server.setup_publisher
    EM::Timer.new(3) do
      server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
        sorted_events = events.sort_by { |check_name, event_json| check_name }
        sorted_events.each_with_index do |(check_name, event_json), index|
          expected = {
            :output => @settings[:client][:name] + ' ' + @settings[:client][:nested][:attribute].to_s + "\n",
            :status => index + 1,
            :flapping => false
          }
          event = JSON.parse(event_json, :symbolize_names => true).sanitize_keys
          assert(event.delete(:occurrences) > 0)
          assert_equal(expected, event)
        end
        server.amq.queue('', :auto_delete => true).bind('graphite', :key => 'sensu.*').subscribe do |metric|
          assert(metric.is_a?(String))
          assert_equal(['sensu', @settings[:client][:name], 'diceroll'].join('.'), metric.split(/\s/).first)
          done
        end
      end
    end
  end

  def test_client_safe_mode
    server, client = bootstrap
    EM::Timer.new(1) do
      check = {
        :name => 'foobar',
        :command => 'true',
        :subscribers => ['a']
      }
      server.publish_check_request(check)
      EM::Timer.new(3) do
        server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
          assert(events.include?('foobar'))
          event = JSON.parse(events['foobar'], :symbolize_names => true)
          assert(event[:output] =~ /safe mode/)
          assert_equal(3, event[:status])
          done
        end
      end
    end
  end

  def test_client_sockets
    server, client = bootstrap
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

  def test_first_master_election
    server1 = Sensu::Server.new(@options)
    server2 = Sensu::Server.new(@options)
    server1.setup_redis
    server2.setup_redis
    server1.setup_rabbitmq
    server2.setup_rabbitmq
    server1.redis.flushall.callback do
      server1.setup_master_monitor
      server2.setup_master_monitor
      EM::Timer.new(1) do
        assert([server1.is_master, server2.is_master].uniq.count == 2)
        done
      end
    end
  end

  def test_failover_master_election
    server1 = Sensu::Server.new(@options)
    server2 = Sensu::Server.new(@options)
    server1.setup_redis
    server2.setup_redis
    server1.setup_rabbitmq
    server2.setup_rabbitmq
    server1.redis.set('lock:master', Time.now.to_i - 60).callback do
      server1.setup_master_monitor
      server2.setup_master_monitor
      EM::Timer.new(1) do
        assert([server1.is_master, server2.is_master].uniq.count == 2)
        done
      end
    end
  end
end
