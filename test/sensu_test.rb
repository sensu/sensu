class TestSensu < Test::Unit::TestCase
  include EventMachine::Test

  def setup
    @options = {:config_file => File.join(File.dirname(__FILE__), 'config.json')}
    config = Sensu::Config.new(@options)
    @settings = config.settings
  end

  def test_read_config_file
    config = Sensu::Config.new(@options)
    settings = config.settings
    assert(settings.key?('client'))
    done
  end

  def test_cli_arguments
    options = Sensu::Config.read_arguments(['-w', '-c', @options[:config_file]])
    assert_equal({:worker => true, :config_file => @options[:config_file]}, options)
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
        assert_equal(@settings['client'], JSON.parse(client_json).reject { |key, value| key == 'timestamp' })
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
        :flapping => false
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
        client_events = Hash[*events].sort_by { |status, value| value }
        client_events.each_with_index do |(key, value), index|
          expected_result = {
            :status => index + 1,
            :output => @settings.client.name + "\n",
            :flapping => false,
            :occurrences => 1
          }
          assert_equal(expected_result, JSON.parse(value).symbolize_keys)
        end
        done
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
    EM.defer(external_source)
    EM.add_timer(1) do
      server.redis.hgetall('events:' + @settings.client.name).callback do |events|
        assert(Hash[*events].include?('external'))
        done
      end
    end
  end
end
