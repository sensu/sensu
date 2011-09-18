$: << File.dirname(__FILE__) + '/../lib' unless $:.include?(File.dirname(__FILE__) + '/../lib/')
require 'rubygems' if RUBY_VERSION < '1.9.0'
gem 'minitest'
require 'minitest/autorun'
require 'em-ventually'
require 'sensu/config'
require 'sensu/server'
require 'sensu/client'

class TestSensu < MiniTest::Unit::TestCase
  include EM::Ventually
  EM::Ventually.total_default = 0.5

  def setup
    @options = { :config_file => File.join(File.dirname(__FILE__), 'config.json') }
    config = Sensu::Config.new(@options)
    config.create_working_directory
    config.purge_working_directory
    @settings = config.settings
  end

  def test_read_config_file
    config = Sensu::Config.new(@options)
    settings = config.settings
    eventually(true) { settings.has_key?('client') }
  end

  def test_create_working_directory
    config = Sensu::Config.new(@options)
    config.create_working_directory
    eventually(true) { File.exists?('/tmp/sensu') }
  end

  def test_keep_alives
    server = Sensu::Server.new(@options)
    client = Sensu::Client.new(@options)
    server.setup_logging
    server.setup_redis
    server.setup_amqp
    server.setup_keep_alives
    client.setup_amqp
    client.setup_keep_alives
    test_client = ''
    EM.add_timer(1) do
      server.redis_connection.get('client:' + @settings['client']['name']).callback do |client_json|
        test_client = JSON.parse(client_json).reject { |key, value| key == 'timestamp' }
      end
    end
    eventually(@settings['client'], :total => 1.5) { test_client }
  end

  def test_handlers
    server = Sensu::Server.new(@options)
    server.setup_logging
    server.setup_handlers
    event = {
      'client' => @settings['client'],
      'check' => {
        'name' => 'test_handlers',
        'handler' => 'default',
        'issued' => Time.now.to_i,
        'status' => 1,
        'output' => 'WARNING\n'
      },
      'occurrences' => 1,
      'action' => 'create'
    }
    server.handle_event(event)
    eventually(true, :total => 2) do
      JSON.parse(File.open('/tmp/sensu/test_handlers', 'rb').read) == event
    end
  end

  def test_publish_subscribe
    server = Sensu::Server.new(@options)
    client = Sensu::Client.new(@options)
    server.setup_logging
    server.setup_redis
    server.setup_amqp
    server.setup_keep_alives
    server.setup_handlers
    server.setup_results
    server.redis_connection.flushall
    client.setup_amqp
    client.setup_keep_alives
    client.setup_subscriptions
    server.setup_publisher(:test => true)
    client_events = Hash.new
    EM.add_timer(1) do
      server.redis_connection.hgetall('events:' + @settings['client']['name']).callback do |events|
        client_events = Hash[*events]
        client_events.each do |key, value|
          client_events[key] = JSON.parse(value)
        end
      end
    end
    parallel do
      @settings['checks'].each_with_index do |(name, details), index|
        eventually({'status' => index + 1, 'output' => @settings['client']['name'] + "\n", "occurrences" => 1}, :total => 1.5) do
          client_events[name]
        end
      end
    end
  end
end
