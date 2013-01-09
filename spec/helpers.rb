require 'rspec'

module Helpers
  def setup_options
    @options = {
      :config_file => File.join(File.dirname(__FILE__), 'config.json'),
      :config_dir => File.join(File.dirname(__FILE__), 'conf.d'),
      :extension_dir => File.join(File.dirname(__FILE__), 'extensions'),
      :log_level => :fatal
    }
  end

  def options
    @options ? @options : setup_options
  end

  def setup_redis
    @redis = EM::Protocols::Redis.connect
    @redis
  end

  def redis
    @redis ? @redis : setup_redis
  end

  def setup_amq
    rabbitmq = AMQP.connect
    @amq = AMQP::Channel.new(rabbitmq)
    @amq
  end

  def amq
    @amq ? @amq : setup_amq
  end

  def epoch
    Time.now.to_i
  end

  def timer(delay, &block)
    periodic_timer = EM::PeriodicTimer.new(delay) do
      block.call
      periodic_timer.cancel
    end
  end

  def async_wrapper(&block)
    EM::run do
      timer(10) do
        raise 'test timed out'
      end
      block.call
    end
  end

  def async_done
    EM::stop_event_loop
  end

  class TestServer < EM::Connection
    include RSpec::Matchers

    attr_accessor :expected

    def receive_data(data)
      data.should eq(expected)
      EM::stop_event_loop
    end
  end
end
