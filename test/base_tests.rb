class TestSensuBase < TestCase
  def setup
    @options = {
      :config_file => File.join(File.dirname(__FILE__), 'config.json'),
      :config_dir => File.join(File.dirname(__FILE__), 'conf.d'),
      :log_level => :error
    }
  end

  def test_read_config_files
    base = Sensu::Base.new(@options)
    settings = base.settings
    assert(settings.check_exists?('a'))
    assert(settings.handler_exists?('new_handler'))
    assert(settings[:checks][:b][:subscribers] == ['a', 'b'])
    assert(settings[:checks][:b][:interval] == 1)
    assert(settings[:checks][:b][:auto_resolve] == false)
    done
  end

  def test_read_env
    base = Sensu::Base.new(@options)
    settings = base.settings
    assert(settings[:rabbitmq].is_a?(Hash))
    ENV['RABBITMQ_URL'] = 'amqp://guest:guest@localhost:5672/'
    settings.load_env
    assert(settings.loaded_env)
    assert_equal(ENV['RABBITMQ_URL'], settings[:rabbitmq])
    done
  end

  def test_set_env
    base = Sensu::Base.new(@options)
    settings = base.settings
    settings.set_env
    expected = [@options[:config_file], @options[:config_dir] + '/snippet.json'].join(':')
    assert_equal(expected, ENV['SENSU_CONFIG_FILES'])
    done
  end

  def test_write_pid
    pid_file = '/tmp/sensu_write_pid'
    Sensu::Base.new(@options.merge(:pid_file => pid_file))
    assert(File.exists?(pid_file), 'PID file does not exist')
    assert_equal(Process.pid.to_s, File.read(pid_file).chomp)
    done
  end
end
