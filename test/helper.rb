require 'rubygems'
require 'em-spec/test'
require 'em-http-request'

Dir.glob(File.dirname(__FILE__) + '/../lib/sensu/*.rb', &method(:require))

module TestUtil
  def setup
    @options = {
      :config_file => File.join(File.dirname(__FILE__), 'config.json'),
      :config_dir => File.join(File.dirname(__FILE__), 'conf.d'),
      :log_level => :error
    }
    base = Sensu::Base.new(@options)
    @settings = base.settings
  end

  def teardown
    Dir.glob('/tmp/sensu_*').each do |file|
      File.delete(file)
    end
    Dir.glob(File.dirname(__FILE__) + '/conf.d/*.tmp.json').each do |file|
      File.delete(file)
    end
  end

  def sanitize_keys(hash)
    hash.reject do |key, value|
      [:timestamp, :issued].include?(key)
    end
  end

  def create_config_snippet(name, content)
    File.open(File.join(File.dirname(__FILE__), 'conf.d', name + '.tmp.json'), 'w') do |file|
      file.write((content.is_a?(Hash) ? content.to_json : content))
    end
  end

  def base_server_client
    server = Sensu::Server.new(@options)
    client = Sensu::Client.new(@options)
    server.setup_redis
    server.redis.flushall
    server.setup_rabbitmq
    server.setup_keepalives
    server.setup_results
    client.setup_rabbitmq
    client.setup_keepalives
    client.setup_subscriptions
    [server, client]
  end

  def event_template(check_options={})
    event = {
      :client => @settings[:client],
      :check => {
        :name => 'event',
        :issued => Time.now.to_i,
        :output => 'WARNING',
        :status => 1,
        :history => [1]
      },
      :occurrences => 1,
      :action => 'create'
    }
    event[:check].merge!(check_options)
    event
  end

  def api_request(uri, method=:get, options={}, &block)
    api = 'http://' + @settings[:api][:host] + ':' + @settings[:api][:port].to_s
    default_options = {
      :head => {
        :authorization => [
          @settings[:api][:user],
          @settings[:api][:password]
        ]
      }
    }
    request_options = default_options.merge(options)
    http = EM::HttpRequest.new(api + uri).send(method, request_options)
    http.callback do
      body = begin
        JSON.parse(http.response, :symbolize_names => true)
      rescue JSON::ParserError
        http.response
      end
      block.call(http, body)
    end
  end
end

if RUBY_VERSION < '1.9.0'
  gem 'test-unit'

  require 'test/unit'

  class TestCase < Test::Unit::TestCase
    include ::EM::Test
    include TestUtil
  end
else
  require 'minitest/unit'

  MiniTest::Unit.autorun

  class TestCase < MiniTest::Unit::TestCase
    include ::EM::Test
    include TestUtil
  end
end
