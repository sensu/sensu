class TestSensuSubdue < TestCase
  def setup
    write_config!
    @options = {
      :config_file => File.join(File.dirname(__FILE__), 'config_subdue.json'),
      :log_level => :error
    }
    config = Sensu::Base.new(@options)
    @settings = config.settings
  end

  def teardown
    File.delete(File.join(File.dirname(__FILE__), 'config_subdue.json'))
  end

  def test_publish_subscribe_subdue
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
    EM::Timer.new(2) do
      server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
        assert events.size > 0, 'Failed to receive events'
        found = events.keys.find_all do |name|
          name.start_with?('subdue')
        end
        refute found.size > 0, "Found subdued event(s): #{found.join(', ')}"
        done
      end
    end
  end

  def test_handler_subdue
    server = Sensu::Server.new(@options)
    client = @settings[:client].sanitize_keys
    file_path = '/tmp/sensu_test_handlers'
    @settings[:checks].each do |check|
      File.delete(file_path) if File.exists?(file_path)
      event = {
        :client => client,
        :check => check.last.merge(
          :handler => 'file', 
          :issued => Time.now.to_i, 
          :status => 1, 
          :history => [1]
        ),
        :occurrences => 1,
        :action => 'create'
      }
      event[:check][:subdue].delete(:at)
      server.handle_event(event)
      sleep(0.5)
      if(check.first.to_s.start_with?('subdue'))
        refute File.exists?(file_path), "File should not exist for: #{check.first}"
      else
        assert File.exists?(file_path), "File should exist for: #{check.first}"
      end
    end
    done
  end

  def write_config!
    config = JSON.parse(
      File.read(
        File.join(
          File.dirname(__FILE__), 'config_subdue.json.orig')
      )
    )
    checks = config['checks']
    checks['subdue_time']['subdue'] = {
      'at' => 'publisher',
      'start' => (Time.now - 3600).strftime('%l:00 %P').strip,
      'end' => (Time.now + 3600).strftime('%l:00 %P').strip
    }
    checks['nonsubdue_time']['subdue'] = {
      'at' => 'publisher',
      'start' => (Time.now + 3600).strftime('%l:00 %P').strip,
      'end' => (Time.now + 7200).strftime('%l:00 %P').strip
    }
    checks['subdue_time_wrap']['subdue'] = {
      'at' => 'publisher',
      'start' => (Time.now - 3600).strftime('%l:00 %P').strip,
      'end' => (Time.now - 7200).strftime('%l:00 %P').strip
    }
    checks['nonsubdue_time_wrap']['subdue'] = {
      'at' => 'publisher',
      'start' => (Time.now + 3600).strftime('%l:00 %P').strip,
      'end' => (Time.now - 7200).strftime('%l:00 %P').strip
    }
    checks['subdue_day']['subdue'] = {
      'at' => 'publisher',
      'days' => Time.now.strftime('%A')
    }
    checks['subdue_days']['subdue'] = {
      'at' => 'publisher',
      'days' => [Time.now.strftime('%A'), 'Monday']
    }
    checks['nonsubdue_day']['subdue'] = {
      'at' => 'publisher',
      'days' => (Time.now + 86400).strftime('%A')
    }
    checks['nonsubdue_days']['subdue'] = {
      'at' => 'publisher',
      'days' => [
        (Time.now + 86400).strftime('%A'),
        (Time.now + 172800).strftime('%A')
      ]
    }
    checks['subdue_exception']['subdue'] = {
      'at' => 'publisher',
      'exceptions' => [{
          :start => (Time.now + 3600).rfc2822,
          :end => (Time.now + 7200)
      }],
      'days' => %w(sunday monday tuesday wednesday thursday friday saturday)
    }
    checks['nonsubdue_exception']['subdue'] = {
      'at' => 'publisher',
      'exceptions' => [{
          :start => (Time.now - 3600).rfc2822,
          :end => (Time.now + 3600).rfc2822
      }],
      'days' => %w(sunday monday tuesday wednesday thursday friday saturday)
    }
    File.open(File.join(File.dirname(__FILE__), 'config_subdue.json'), 'w') do |file|
      file.write config.to_json
    end
  end
  
end
