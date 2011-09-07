$: << File.dirname(__FILE__) + '/../lib' unless $:.include?(File.dirname(__FILE__) + '/../lib/')
require 'rubygems' if RUBY_VERSION < '1.9.0'
gem 'minitest'
require 'minitest/autorun'
require 'rest_client'
require 'sensu/api'

api = Process.fork do
  Sensu::API.run(:config_file => File.join(File.dirname(__FILE__), 'config.json'))
end

class TestSensuAPI < MiniTest::Unit::TestCase
  def test_get_clients
    response = RestClient.get 'localhost:4567/clients'
    assert_block "Unexpected response body" do
      JSON.parse(response.body).kind_of?(Array)
    end
    assert_equal(200, response.code.to_i)
  end

  def test_get_events
    response = RestClient.get 'localhost:4567/events'
    assert_block "Unexpected response body" do
      JSON.parse(response.body).kind_of?(Hash)
    end
    assert_equal(200, response.code.to_i)
  end

  def test_get_nonexistent_client
    begin
      response = RestClient.get 'localhost:4567/client/nonexistent'
      code = response.code.to_i
    rescue => error
      code = error.response.code.to_i
    end
    assert_equal(404, code)
  end

  def test_delete_nonexistent_client
    begin
      response = RestClient.delete 'localhost:4567/client/nonexistent'
      code = response.code.to_i
    rescue => error
      code = error.response.code.to_i
    end
    assert_equal(404, code)
  end
end

MiniTest::Unit.after_tests do
  Process.kill('KILL', api)
end
