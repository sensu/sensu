class TestSensuSubdue < TestCase
  def setup
    write_config!
    @options = {
      :config_file => File.join(File.dirname(__FILE__), 'subdue_config.json'),
      :log_level => :error
    }
    base = Sensu::Base.new(@options)
    @settings = base.settings
  end

  def teardown
    File.delete(File.join(File.dirname(__FILE__), 'subdue_config.json'))
  end

  def write_config!
    config_file = File.read(File.join(File.dirname(__FILE__), 'subdue_config.json.orig'))
    config = JSON.parse(config_file, :symbolize_names => true)
    config[:checks][:subdue_time][:subdue] = {
      :at => 'publisher',
      :start => (Time.now - 3600).strftime('%l:00 %p').strip,
      :end => (Time.now + 3600).strftime('%l:00 %p').strip
    }
    config[:checks][:nonsubdue_time][:subdue] = {
      :at => 'publisher',
      :start => (Time.now + 3600).strftime('%l:00 %p').strip,
      :end => (Time.now + 7200).strftime('%l:00 %p').strip
    }
    config[:checks][:subdue_time_wrap][:subdue] = {
      :at => 'publisher',
      :start => (Time.now - 3600).strftime('%l:00 %p').strip,
      :end => (Time.now - 7200).strftime('%l:00 %p').strip
    }
    config[:checks][:nonsubdue_time_wrap][:subdue] = {
      :at => 'publisher',
      :start => (Time.now + 3600).strftime('%l:00 %p').strip,
      :end => (Time.now - 7200).strftime('%l:00 %p').strip
    }
    config[:checks][:subdue_day][:subdue] = {
      :at => 'publisher',
      :days => Time.now.strftime('%A')
    }
    config[:checks][:subdue_days][:subdue] = {
      :at => 'publisher',
      :days => [Time.now.strftime('%A'), 'Monday']
    }
    config[:checks][:nonsubdue_day][:subdue] = {
      :at => 'publisher',
      :days => (Time.now + 86400).strftime('%A')
    }
    config[:checks][:nonsubdue_days][:subdue] = {
      :at => 'publisher',
      :days => [
        (Time.now + 86400).strftime('%A'),
        (Time.now + 172800).strftime('%A')
      ]
    }
    config[:checks][:subdue_exception][:subdue] = {
      :at => 'publisher',
      :exceptions => [{
        :start => (Time.now + 3600).rfc2822,
        :end => (Time.now + 7200)
      }],
      :days => %w[sunday monday tuesday wednesday thursday friday saturday]
    }
    config[:checks][:nonsubdue_exception][:subdue] = {
      :at => 'publisher',
      :exceptions => [{
        :start => (Time.now - 3600).rfc2822,
        :end => (Time.now + 3600).rfc2822
      }],
      :days => %w[sunday monday tuesday wednesday thursday friday saturday]
    }
    File.open(File.join(File.dirname(__FILE__), 'subdue_config.json'), 'w') do |file|
      file.write config.to_json
    end
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
    EM::Timer.new(4) do
      server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
        assert(events.size > 0, 'Failed to receive events')
        found = events.keys.find_all do |name|
          name.start_with?('subdue')
        end
        assert(found.size == 0, 'Found subdued event(s): ' + found.join(', '))
        done
      end
    end
  end

  def test_handler_subdue
    server = Sensu::Server.new(@options)
    client = @settings[:client].sanitize_keys
    @settings.checks.each do |check|
      file_path = '/tmp/sensu_' + check[:name]
      if File.exists?(file_path)
        File.delete(file_path)
      end
      event = {
        :client => client,
        :check => check.merge(
          :handler => 'file',
          :issued => Time.now.to_i,
          :output => 'foobar',
          :status => 1,
          :history => [1]
        ),
        :occurrences => 1,
        :action => 'create'
      }
      event[:check][:subdue].delete(:at)
      server.handle_event(event)
    end
    EM::Timer.new(2) do
      @settings.checks.each do |check|
        file_path = '/tmp/sensu_' + check[:name]
        if(check[:name].start_with?('subdue'))
          assert(!File.exists?(file_path), 'File should not exist for: ' + check[:name])
        else
          assert(File.exists?(file_path), 'File should exist for: ' + check[:name])
        end
      end
      done
    end
  end
end
