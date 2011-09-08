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
    test_client_name = ''
    EM.add_timer(1) do
      server.redis.get('client:' + @settings['client']['name']).callback do |client_json|
        test_client = JSON.parse(client_json)
        test_client_name = test_client['name']
      end
    end
    eventually(@settings['client']['name'], :every => 1, :total => 2) { test_client_name }
  end

  def test_handlers
    server = Sensu::Server.new(@options)
    server.setup_logging
    server.setup_handlers
    event = {
      'client' => @settings['client'],
      'check' => {
        'handler' => 'default'
      },
      'status' => 1,
      'output' => 'WARNING\n'
    }
    server.handle_event(event)
    eventually(true, :every => 0.5, :total => 1) do
      JSON.parse(File.open('/tmp/sensu/test_handlers', 'rb').read) == event
    end
  end
end
