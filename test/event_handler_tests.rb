class TestSensuEventHandlers < TestCase
  def test_pipe_handler
    server = Sensu::Server.new(@options)
    event = event_template(:handler => 'file')
    server.handle_event(event)
    EM::Timer.new(2) do
      assert(File.exists?('/tmp/sensu_event'))
      output_file = File.open('/tmp/sensu_event', 'r')
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

  def test_handler_severities
    server = Sensu::Server.new(@options)
    event1 = event_template(:handler => 'filter_severity', :status => 2)
    event2 = event_template(:handler => 'filter_severity')
    server.handle_event(event1)
    server.handle_event(event2)
    EM::Timer.new(2) do
      assert(File.exists?('/tmp/sensu_event'))
      output_file = File.open('/tmp/sensu_event')
      output = JSON.parse(output_file.read, :symbolize_names => true)
      assert_equal(event1, output)
      done
    end
  end

  def test_mutated_event_data
    server = Sensu::Server.new(@options)
    event = event_template(:handler => 'mutated')
    server.handle_event(event)
    EM::Timer.new(3) do
      assert(File.exists?('/tmp/sensu_event'))
      expected = event.merge(:mutated => true)
      output_file = File.open('/tmp/sensu_event', 'r')
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
      assert(!File.exists?('/tmp/sensu_event'))
      done
    end
  end

  def test_derive_handlers
    server = Sensu::Server.new(@options)
    handler_list = ['default', 'file', 'file', 'nonexistent']
    expected = [
      @settings[:handlers][:stdout],
      @settings[:handlers][:file]
    ]
    handlers = server.derive_handlers(handler_list)
    assert_equal(expected, handlers)
    done
  end
end
