class TestSensuPublishSubscribe < TestCase
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
        standalone = JSON.parse(events['standalone'], :symbolize_names => true)
        assert_equal(@settings[:client][:name], standalone[:output])
        assert_equal(1, standalone[:status])
        assert(events.has_key?('timed'))
        timed = JSON.parse(events['timed'], :symbolize_names => true)
        if RUBY_VERSION < '1.9.0'
          assert_equal(@settings[:client][:name], timed[:output])
          assert_equal(1, timed[:status])
        else
          assert_equal('Execution timed out', timed[:output])
          assert_equal(2, timed[:status])
        end
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
        :command => 'echo && exit 255',
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
        :command => 'echo && exit 255',
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
end
