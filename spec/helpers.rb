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

  def keepalive_queue(&block)
    queue = amq.queue('keepalives')
    queue.bind(amq.direct('keepalives')) do
      block.call(queue)
    end
  end

  def result_queue(&block)
    queue = amq.queue('results')
    queue.bind(amq.direct('results')) do
      block.call(queue)
    end
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

  def api_test(&block)
    async_wrapper do
      Sensu::API.test(options)
      timer(0.5) do
        block.call
      end
    end
  end

  def with_stdout_redirect(&block)
    stdout = STDOUT.clone
    STDOUT.reopen(File.open('/dev/null', 'w'))
    block.call
    STDOUT.reopen(stdout)
  end

  def epoch
    Time.now.to_i
  end

  def client_template
    {
      :name => 'i-424242',
      :address => '127.0.0.1',
      :subscriptions => [
        'test'
      ],
      :keepalive => {
        :thresholds => {
          :warning => 60,
          :critical => 120
        }
      }
    }
  end

  def check_template
    {
      :name => 'foobar',
      :command => 'echo -n WARNING && exit 1',
      :issued => epoch
    }
  end

  def result_template
    check = check_template
    check[:output] = 'WARNING'
    check[:status] = 1
    {
      :client => 'i-424242',
      :check => check
    }
  end

  def event_template
    client = client_template
    client[:timestamp] = epoch
    check = check_template
    check[:output] = 'WARNING'
    check[:status] = 1
    check[:history] = [1]
    {
      :client => client,
      :check => check,
      :occurrences => 1,
      :action => :create
    }
  end

  def api_request(uri, method=:get, options={}, &block)
    default_options = {
      :head => {
        :authorization => [
          'foo',
          'bar'
        ]
      }
    }
    request_options = default_options.merge(options)
    if request_options[:body].is_a?(Hash) || request_options[:body].is_a?(Array)
      request_options[:body] = Oj.dump(request_options[:body])
    end
    http = EM::HttpRequest.new('http://localhost:4567' + uri).send(method, request_options)
    http.callback do
      body = case
      when http.response.empty?
        http.response
      else
        Oj.load(http.response)
      end
      block.call(http, body)
    end
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

RSpec::Matchers.define :contain do |block|
  match do |actual|
    actual.any? do |item|
      block.call(item)
    end
  end
end
