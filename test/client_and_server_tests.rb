class TestSensu < TestCase
  def setup
    @options = {
      :config_file => File.join(File.dirname(__FILE__), 'config.json'),
      :config_dir => File.join(File.dirname(__FILE__), 'conf.d'),
      :log_level => :error
    }
    config = Sensu::Config.new(@options)
    @settings = config.settings
  end

  def test_read_config_file
    config = Sensu::Config.new(@options)
    settings = config.settings
    assert(settings.key?('client'))
    done
  end

  def test_config_dir_snippets
    config = Sensu::Config.new(@options)
    settings = config.settings
    assert(settings.handlers.key?('new_handler'))
    assert(settings.checks.b.subscribers == ['a', 'b'])
    assert(settings.checks.b.interval == 1)
    assert(settings.checks.b.auto_resolve == false)
    done
  end

  def test_cli_arguments
    options = Sensu::CLI.read([
      '-c', @options[:config_file],
      '-d', @options[:config_dir],
      '-v',
      '-l', '/tmp/sensu_test.log',
      '-p', '/tmp/sensu_test.pid',
      '-b'
    ])
    expected = {
      :config_file => @options[:config_file],
      :config_dir => @options[:config_dir],
      :verbose => true,
      :log_file => '/tmp/sensu_test.log',
      :pid_file => '/tmp/sensu_test.pid',
      :daemonize => true
    }
    assert_equal(expected, options)
    done
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
      server.redis.get('client:' + @settings.client.name).callback do |client_json|
        assert_equal(@settings.client, JSON.parse(client_json).reject { |key, value| key == 'timestamp' })
        done
      end
    end
  end

  def test_handlers
    server = Sensu::Server.new(@options)
    event = Hashie::Mash.new(
      :client => @settings.client.reject { |key, value| key == 'timestamp' },
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
    )
    server.handle_event(event)
    EM::Timer.new(2) do
      assert_equal(event.to_hash, JSON.parse(File.open('/tmp/sensu_test_handlers', 'rb').read))
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
    client.setup_standalone(:test => true)
    server.setup_publisher(:test => true)
    EM::Timer.new(1) do
      server.redis.hgetall('events:' + @settings.client.name).callback do |events|
        sorted_events = events.sort_by { |status, value| value }
        sorted_events.each_with_index do |(key, value), index|
          expected = {
            :output => @settings.client.name + ' ' + @settings.client.custom.nested.attribute.to_s + "\n",
            :status => index + 1,
            :flapping => false,
            :occurrences => 1
          }
          assert_equal(expected, (JSON.parse(value).reject { |key, value| key == 'issued' }).symbolize_keys)
        end
        server.amq.queue('', :auto_delete => true).bind('graphite', :key => 'sensu.*').subscribe do |metric|
          assert(metric.is_a?(String))
          assert_equal(['sensu', @settings.client.name, 'diceroll'].join('.'), metric.split(/\s/).first)
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
      tcp_socket.write('{"name": "tcp_socket", "output": "test", "status": 1}')
      tcp_socket.recv(2)
    end
    callback = proc do |response|
      assert_equal('ok', response)
      EM::Timer.new(2) do
        server.redis.hgetall('events:' + @settings.client.name).callback do |events|
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
