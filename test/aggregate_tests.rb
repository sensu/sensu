class TestSensuAggregate < TestCase
  def setup
    @options = {
      :config_file => File.join(File.dirname(__FILE__), 'config.json'),
      :config_dir => File.join(File.dirname(__FILE__), 'conf.d'),
      :log_level => :error
    }
    base = Sensu::Base.new(@options)
    @settings = base.settings
  end

  def test_check_aggregate
    assert(true)
    done
  end
end
