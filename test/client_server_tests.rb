class TestSensuClientServer < TestCase
  def test_pipe_handler
    server = Sensu::Server.new(@options)
    event = event_template(:handler => 'file')
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
    event = event_template(:handler => 'tcp_socket')
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
    event = event_template(:handler => 'udp_socket')
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

  def test_amqp_handler
    server = Sensu::Server.new(@options)
    server.setup_rabbitmq
    event = event_template(:handler => 'amqp_exchange')
    EM::Timer.new(2) do
      server.handle_event(event)
    end
    server.amq.direct('events')
    server.amq.queue('', :auto_delete => true).bind('events').subscribe do |event_json|
      assert(event.to_json, event_json)
      done
    end
  end

  def test_mutators
    server = Sensu::Server.new(@options)
    event = event_template(:handler => 'tagged')
    server.handle_event(event)
    EM::Timer.new(2) do
      assert(File.exists?('/tmp/sensu_example'))
      expected = event.merge(:mutated => true)
      output_file = File.open('/tmp/sensu_example', 'r')
      output = JSON.parse(output_file.read, :symbolize_names => true)
      assert_equal(expected, output)
      done
    end
  end

  def test_missing_mutator
    server = Sensu::Server.new(@options)
    event = event_template(:handler => 'missing_mutator')
    server.handle_event(event)
    EM::Timer.new(2) do
      assert(!File.exists?('/tmp/sensu_example'))
      done
    end
  end

  def test_built_in_mutator_only_output
    server = Sensu::Server.new(@options)
    handler = @settings[:handlers][:only_output]
    event = event_template(:output => "foo\nbar")
    assert_equal("foo\nbar", server.mutate_event_data(handler, event))
    done
  end

  def test_built_in_amqp_mutator_only_output_split
    server = Sensu::Server.new(@options)
    handler = @settings[:handlers][:only_output_split]
    event = event_template(:output => "foo\nbar")
    assert_equal(['foo', 'bar'], server.mutate_event_data(handler, event))
    done
  end

  def test_keepalives
    server, client = base_server_client
    EM::Timer.new(1) do
      server.redis.get('client:' + @settings[:client][:name]).callback do |client_json|
        client_attributes = sanitize_keys(JSON.parse(client_json, :symbolize_names => true))
        assert_equal(@settings[:client], client_attributes)
        done
      end
    end
  end

  def test_standalone_checks
    server, client = base_server_client
    client.setup_standalone
    EM::Timer.new(3) do
      server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
        assert(events.has_key?('standalone'))
        event = JSON.parse(events['standalone'], :symbolize_names => true)
        assert_equal(@settings[:client][:name], event[:output])
        assert_equal(1, event[:status])
        done
      end
    end
  end

  def test_check_command_tokens
    server, client = base_server_client
    server.setup_publisher
    EM::Timer.new(3) do
      server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
        assert(events.has_key?('tokens'))
        expected = [@settings[:client][:name], @settings[:client][:nested][:attribute]].join(' ')
        tokens = JSON.parse(events['tokens'], :symbolize_names => true)
        assert_equal(expected, tokens[:output])
        assert_equal(2, tokens[:status])
        assert(events.has_key?('tokens_fail'))
        tokens_fail = JSON.parse(events['tokens_fail'], :symbolize_names => true)
        assert(tokens_fail[:output] =~ /missing/i)
        assert_equal(3, tokens_fail[:status])
        done
      end
    end
  end

  def test_client_safe_mode_default
    server, client = base_server_client
    EM::Timer.new(1) do
      check = {
        :name => 'arbitrary',
        :command => 'exit 255',
        :subscribers => ['test']
      }
      server.publish_check_request(check)
      EM::Timer.new(3) do
        server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
          assert(events.include?('arbitrary'))
          event = JSON.parse(events['arbitrary'], :symbolize_names => true)
          assert_equal(255, event[:status])
          done
        end
      end
    end
  end

  def test_client_safe_mode_enabled
    enable_safe_mode = {
      :client => {
        :safe_mode => true
      }
    }
    create_config_snippet('safe_mode', enable_safe_mode)
    server, client = base_server_client
    EM::Timer.new(1) do
      check = {
        :name => 'arbitrary',
        :command => 'exit 255',
        :subscribers => ['test']
      }
      server.publish_check_request(check)
      EM::Timer.new(3) do
        server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
          assert(events.include?('arbitrary'))
          event = JSON.parse(events['arbitrary'], :symbolize_names => true)
          assert(event[:output] =~ /safe mode/)
          assert_equal(3, event[:status])
          done
        end
      end
    end
  end

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
