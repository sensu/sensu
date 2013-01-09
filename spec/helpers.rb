require 'rspec'

module Helpers
  def options
    @options = {
      :config_file => File.join(File.dirname(__FILE__), 'config.json'),
      :config_dir => File.join(File.dirname(__FILE__), 'conf.d'),
      :extension_dir => File.join(File.dirname(__FILE__), 'extensions'),
      :log_level => :fatal
    }
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
    EM::Timer.new(delay) do
      block.call
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
end
