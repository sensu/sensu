class TestSensuSubdue < TestCase
  def setup
    generate_config_snippet
    super
  end

  def check_definition_template(check_name)
    {
      check_name.to_sym => {
        :command => 'echo -n test && exit 1',
        :subscribers => ['test'],
        :interval => 1
      }
    }
  end

  def subdue_check_names
    check_names = Array.new
    %w[time time_wrap day days exception].each do |word|
      check_names.push('subdue_' + word)
      check_names.push('nonsubdue_' + word)
    end
    check_names
  end

  def subdue_config_template
    subdue_checks = Hash.new
    subdue_check_names.each do |check_name|
      subdue_checks.merge!(check_definition_template(check_name))
    end
    {:checks => subdue_checks}
  end

  def generate_config_snippet
    subdue_config = subdue_config_template
    subdue_config[:checks][:subdue_time][:subdue] = {
      :at => 'publisher',
      :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
      :end => (Time.now + 3600).strftime('%l:00 %p').strip
    }
    subdue_config[:checks][:nonsubdue_time][:subdue] = {
      :at => 'publisher',
      :begin => (Time.now + 3600).strftime('%l:00 %p').strip,
      :end => (Time.now + 7200).strftime('%l:00 %p').strip
    }
    subdue_config[:checks][:subdue_time_wrap][:subdue] = {
      :at => 'publisher',
      :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
      :end => (Time.now - 7200).strftime('%l:00 %p').strip
    }
    subdue_config[:checks][:nonsubdue_time_wrap][:subdue] = {
      :at => 'publisher',
      :begin => (Time.now + 3600).strftime('%l:00 %p').strip,
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
          :begin => (Time.now + 3600).rfc2822,
          :end => (Time.now + 7200)
        }
      ]
    }
    subdue_config[:checks][:nonsubdue_exception][:subdue] = {
      :at => 'publisher',
      :days => %w[sunday monday tuesday wednesday thursday friday saturday],
      :exceptions => [
        {
          :begin => (Time.now - 3600).rfc2822,
          :end => (Time.now + 3600).rfc2822
        }
      ]
    }
    create_config_snippet('subdue', subdue_config)
  end

  def test_subdue_at_publisher
    server, client = base_server_client
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

  def test_subdue_at_handler
    server = Sensu::Server.new(@options)
    subdue_test_checks = @settings.checks.select do |check|
      check[:name] =~ /subdue/
    end
    subdue_test_checks.each do |check|
      event = event_template(check.merge(:handler => 'file'))
      event[:check][:subdue].delete(:at)
      server.handle_event(event)
    end
    EM::Timer.new(5) do
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
