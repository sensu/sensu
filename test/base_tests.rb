class TestSensuBase < TestCase
  def test_read_config_files
    base = Sensu::Base.new(@options)
    settings = base.settings
    assert(settings.mutator_exists?(:tag))
    assert(settings.handler_exists?(:stdout))
    assert(settings.check_exists?(:standalone))
    done
  end

  def test_config_snippets
    new_handler = {
      :handlers => {
        :new_handler => {
          :type => 'pipe',
          :command => 'cat'
        }
      }
    }
    merge_check = {
      :checks => {
        :merger => {
          :interval => 60,
          :auto_resolve => false
        }
      }
    }
    create_config_snippet('new_handler', new_handler)
    create_config_snippet('merge_check', merge_check)
    base = Sensu::Base.new(@options)
    settings = base.settings
    assert(settings.handler_exists?(:new_handler))
    assert_equal('pipe', settings[:handlers][:new_handler][:type])
    assert_equal('cat', settings[:handlers][:new_handler][:command])
    assert(settings.check_exists?(:merger))
    assert('echo', settings[:checks][:merger][:command])
    assert_equal(60, settings[:checks][:merger][:interval])
    assert_equal(false, settings[:checks][:merger][:auto_resolve])
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
    create_config_snippet('snippet', Hash.new)
    base = Sensu::Base.new(@options)
    settings = base.settings
    settings.set_env
    expected = [@options[:config_file], @options[:config_dir] + '/snippet.tmp.json'].join(':')
    assert_equal(expected, ENV['SENSU_CONFIG_FILES'])
    done
  end

  def test_load_extensions
    base = Sensu::Base.new(@options)
    extensions = base.extensions
    assert(extensions.mutator_exists?('opentsdb'))
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
