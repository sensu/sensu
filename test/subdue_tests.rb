class TestSensuSubdue < TestCase
  def setup
    generate_snippet
    @options = {
      :config_file => File.join(File.dirname(__FILE__), 'config.json'),
      :config_dir => File.join(File.dirname(__FILE__), 'conf.d'),
      :log_level => :error
    }
    base = Sensu::Base.new(@options)
    @settings = base.settings
  end

  def generate_snippet
    template_file = File.join(File.dirname(__FILE__), 'conf.d', 'subdue.template')
    template_contents = File.read(template_file)
    subdue_config = JSON.parse(template_contents, :symbolize_names => true)
    subdue_config[:checks][:subdue_time][:subdue] = {
      :at => 'publisher',
      :start => (Time.now - 3600).strftime('%l:00 %p').strip,
      :end => (Time.now + 3600).strftime('%l:00 %p').strip
    }
    subdue_config[:checks][:nonsubdue_time][:subdue] = {
      :at => 'publisher',
      :start => (Time.now + 3600).strftime('%l:00 %p').strip,
      :end => (Time.now + 7200).strftime('%l:00 %p').strip
    }
    subdue_config[:checks][:subdue_time_wrap][:subdue] = {
      :at => 'publisher',
      :start => (Time.now - 3600).strftime('%l:00 %p').strip,
      :end => (Time.now - 7200).strftime('%l:00 %p').strip
    }
    subdue_config[:checks][:nonsubdue_time_wrap][:subdue] = {
      :at => 'publisher',
      :start => (Time.now + 3600).strftime('%l:00 %p').strip,
      :end => (Time.now - 7200).strftime('%l:00 %p').strip
    }
    subdue_config[:checks][:subdue_day][:subdue] = {
      :at => 'publisher',
      :days => [
        Time.now.strftime('%A')
      ]
    }
    subdue_config[:checks][:subdue_days][:subdue] = {
      :at => 'publisher',
      :days => [
        Time.now.strftime('%A'),
        'Monday'
      ]
    }
    subdue_config[:checks][:nonsubdue_day][:subdue] = {
      :at => 'publisher',
      :days => [
        (Time.now + 86400).strftime('%A')
      ]
    }
    subdue_config[:checks][:nonsubdue_days][:subdue] = {
      :at => 'publisher',
      :days => [
        (Time.now + 86400).strftime('%A'),
        (Time.now + 172800).strftime('%A')
      ]
    }
    subdue_config[:checks][:subdue_exception][:subdue] = {
      :at => 'publisher',
      :days => %w[sunday monday tuesday wednesday thursday friday saturday],
      :exceptions => [
        {
          :start => (Time.now + 3600).rfc2822,
          :end => (Time.now + 7200)
        }
      ]
    }
    subdue_config[:checks][:nonsubdue_exception][:subdue] = {
      :at => 'publisher',
      :days => %w[sunday monday tuesday wednesday thursday friday saturday],
      :exceptions => [
        {
          :start => (Time.now - 3600).rfc2822,
          :end => (Time.now + 3600).rfc2822
        }
      ]
    }
    create_config_snippet('subdue', subdue_config)
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
    server.setup_publisher
    EM::Timer.new(4) do
      server.redis.hgetall('events:' + @settings[:client][:name]).callback do |events|
        assert(events.size > 0, 'Failed to receive events')
        found = events.keys.find_all do |check_name|
          check_name.start_with?('subdue')
        end
        assert(found.size == 0, 'Found subdued event(s): ' + found.join(', '))
        done
      end
    end
  end

  def test_handler_subdue
    server = Sensu::Server.new(@options)
    subdue_test_checks = @settings.checks.select do |check|
      check[:name] =~ /subdue/
    end
    subdue_test_checks.each do |check|
      event = {
        :client => @settings[:client],
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
    EM::Timer.new(4) do
      subdue_test_checks.each do |check|
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
