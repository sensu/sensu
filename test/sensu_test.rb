$: << File.dirname(__FILE__) + '/../lib' unless $:.include?(File.dirname(__FILE__) + '/../lib/')
require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'minitest/autorun'
require 'em-ventually/minitest'
require 'sensu/config'
require 'sensu/server'
require 'sensu/client'

class TestSensu < MiniTest::Unit::TestCase
  EM::Ventually.total_default = 0.5

  def test_read_config_file
    config = Sensu::Config.new(:config_file => File.join(File.dirname(__FILE__), 'config.json'))
    settings = config.settings
    eventually(true) { settings.has_key?('client') }
  end

  def test_create_working_directory
    config = Sensu::Config.new(:config_file => File.join(File.dirname(__FILE__), 'config.json'))
    config.create_working_directory
    eventually(true) { File.exists?('/tmp/sensu') }
  end
end
