class TestSensu < Test::Unit::TestCase
  include EventMachine::Test

  def setup
    @options = {
      :config_file => File.join(File.dirname(__FILE__), 'config.json'),
      :config_dir  => File.join(File.dirname(__FILE__), 'conf.d')
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
    assert(settings.checks.b.subscribers == ['b'])
    assert(settings.checks.b.interval == 1)
    assert(settings.checks.b.auto_resolve == false)
    done
  end

  def test_cli_arguments
    options = Sensu::Config.read_arguments(['-c', @options[:config_file], '-d', @options[:config_dir], '-v', '-l', '/tmp/sensu_test.log'])
    expected = {
      :config_file => @options[:config_file],
      :config_dir => @options[:config_dir],
      :verbose => true,
      :log_file => '/tmp/sensu_test.log'
    }
    assert_equal(expected, options)
    done
  end

  def test_keepalives
    server = Sensu::Server.new(@options)
    client = Sensu::Client.new(@options)
    server.setup_redis
    server.setup_amqp
    server.setup_keepalives
    client.setup_amqp
    client.setup_keepalives
    EM.add_timer(1) do
      server.redis.get('client:' + @settings.client.name).callback do |client_json|
        assert_equal(@settings.client, JSON.parse(client_json).reject { |key, value| key == 'timestamp' })
        done
      end
    end
  end

  def test_handlers
    server = Sensu::Server.new(@options)
    event = Hashie::Mash.new({
      :client => @settings.client,
      :check => {
        :name => 'test_handlers',
        :handler => 'default',
        :issued => Time.now.to_i,
        :status => 1,
        :output => 'WARNING\n',
        :history => [1]
      },
      :occurrences => 1,
      :action => 'create'
    })
    server.handle_event(event)
    EM.add_timer(1) do
      assert_equal(event.to_hash, JSON.parse(File.open('/tmp/sensu_test_handlers', 'rb').read))
      done
    end
  end

  def test_publish_subscribe
    server = Sensu::Server.new(@options)
    client = Sensu::Client.new(@options)
    server.setup_redis
    server.setup_amqp
    server.redis.flushall
    server.setup_keepalives
    server.setup_results
    client.setup_amqp
    client.setup_keepalives
    client.setup_subscriptions
    server.setup_publisher(:test => true)
    EM.add_timer(1) do
      server.redis.hgetall('events:' + @settings.client.name).callback do |events|
        sorted_events = events.sort_by { |status, value| value }
        sorted_events.each_with_index do |(key, value), index|
          expected = {
            :status => index + 1,
            :output => @settings.client.name + "\n",
            :flapping => false,
            :occurrences => 1
          }
          assert_equal(expected, JSON.parse(value).symbolize_keys)
        end
        server.amq.queue(String.unique, :exclusive => true).bind('graphite').subscribe do |metric|
          assert(metric.is_a?(String))
          assert_equal(metric.split(' ').first, ['sensu', @settings.client.name, 'diceroll'].join('.'))
          done
        end
      end
    end
  end

  def test_client_socket
    server = Sensu::Server.new(@options)
    client = Sensu::Client.new(@options)
    server.setup_redis
    server.setup_amqp
    server.redis.flushall
    server.setup_keepalives
    client.setup_amqp
    client.setup_keepalives
    server.setup_results
    client.setup_socket
    external_source = proc do
      socket = TCPSocket.open('127.0.0.1', 3030)
      socket.write('{"name": "external", "status": 1, "output": "test"}')
    end
    callback = proc do
      EM.add_timer(1.5) do
        server.redis.hgetall('events:' + @settings.client.name).callback do |events|
          assert(events.include?('external'))
          done
        end
      end
    end
    EM.defer(external_source, callback)
  end

  def test_first_master_election
    server1 = Sensu::Server.new(@options)
    server2 = Sensu::Server.new(@options)
    server1.setup_redis
    server2.setup_redis
    server1.setup_amqp
    server2.setup_amqp
    server1.redis.flushall
    server1.setup_master_monitor
    server2.setup_master_monitor
    EM.add_timer(1) do
      assert([server1.is_master, server2.is_master].uniq.count == 2)
      done
    end
  end

  def test_failover_master_election
    server1 = Sensu::Server.new(@options)
    server2 = Sensu::Server.new(@options)
    server1.setup_redis
    server2.setup_redis
    server1.setup_amqp
    server2.setup_amqp
    server1.redis.flushall
    server1.redis.set('lock:master', Time.now.to_i - 60).callback do
      server1.setup_master_monitor
      server2.setup_master_monitor
      EM.add_timer(1) do
        assert([server1.is_master, server2.is_master].uniq.count == 2)
        done
      end
    end
  end
end
