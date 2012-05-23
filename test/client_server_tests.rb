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

  def test_keepalives
    server = Sensu::Server.new(@options)
    client = Sensu::Client.new(@options)
    server.setup_redis
    server.setup_rabbitmq
    server.setup_keepalives
    client.setup_rabbitmq
    client.setup_keepalives
    EM::Timer.new(1) do
      server.redis.get('client:' + @settings[:client][:name]).callback do |client_json|
        client = JSON.parse(client_json, :symbolize_names => true).sanitize_keys
        assert_equal(@settings[:client], client)
        done
      end
    end
  end

  def test_handlers
    server = Sensu::Server.new(@options)
    client = @settings[:client].sanitize_keys
    event = {
      :client => client,
      :check => {
        :name => 'test_handlers',
        :output => 'WARNING\n',
        :status => 1,
        :issued => Time.now.to_i,
        :handler => 'file',
        :history => [1]
      },
      :occurrences => 1,
      :action => 'create'
    }
    server.handle_event(event)
    EM::Timer.new(2) do
      assert(File.exists?('/tmp/sensu_test_handlers'))
      handler_output_file = File.open('/tmp/sensu_test_handlers', 'rb').read
      handler_output = JSON.parse(handler_output_file, :symbolize_names => true)
      assert_equal(event, handler_output)
      done
    end
  end

  def test_publish_subscribe
    server = Sensu::Server.new(@options)
    client = Sensu::Client.new(@options)
    server.setup_redis
    server.setup_rabbitmq
    server.redis.flushall
    server.setup_keepalives
    server.setup_results
    client.setup_rabbitmq
    client.setup_keepalives
    client.setup_subscriptions
    client.setup_standalone
    server.setup_publisher
    EM::Timer.new(1) do
      server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
        sorted_events = events.sort_by { |check_name, event_json| check_name }
        sorted_events.each_with_index do |(check_name, event_json), index|
          expected = {
            :output => @settings[:client][:name] + ' ' + @settings[:client][:nested][:attribute].to_s + "\n",
            :status => index + 1,
            :flapping => false,
            :occurrences => 1
          }
          event = JSON.parse(event_json, :symbolize_names => true).sanitize_keys
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

  def test_client_sockets
    server = Sensu::Server.new(@options)
    client = Sensu::Client.new(@options)
    server.setup_redis
    server.setup_rabbitmq
    server.redis.flushall
    server.setup_keepalives
    client.setup_rabbitmq
    client.setup_keepalives
    server.setup_results
    client.setup_sockets
    external_source = proc do
      udp_socket = UDPSocket.new
      udp_socket.send('{"name": "udp_socket", "output": "one", "status": 1}', 0, '127.0.0.1', 3030)
      udp_socket.send('{"name": "udp_socket", "output": "two", "status": 1}', 0, '127.0.0.1', 3030)
      tcp_socket = TCPSocket.open('127.0.0.1', 3030)
      tcp_socket.write('{"name": "tcp_socket", "output": "only", "status": 1}')
      tcp_socket.recv(2)
    end
    callback = proc do |response|
      assert_equal('ok', response)
      EM::Timer.new(2) do
        server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
          assert(events.include?('udp_socket'))
          assert(events.include?('tcp_socket'))
          done
        end
      end
    end
    EM::Timer.new(2) do
      EM::defer(external_source, callback)
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
