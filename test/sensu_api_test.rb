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
  def setup
    RestClient.post 'localhost:4567/test', nil
  end

  def test_get_clients
    response = RestClient.get 'localhost:4567/clients'
    assert_block "Unexpected response body" do
      JSON.parse(response.body).is_a?(Array)
    end
    contains = false
    assert_block "Response doesn't include the test client" do
      JSON.parse(response.body).each do |client|
        contains = true if client['name'] == 'test'
      end
      contains
    end
    assert_equal(200, response.code.to_i)
  end

  def test_get_events
    response = RestClient.get 'localhost:4567/events'
    assert_block "Unexpected response body" do
      JSON.parse(response.body).is_a?(Hash)
    end
    contains = false
    assert_block "Response doesn't include the test event" do
      JSON.parse(response.body).each do |client, events|
        if client == 'test'
          events.each do |check, event|
            contains = true if check == 'test'
          end
        end
      end
      contains
    end
    assert_equal(200, response.code.to_i)
  end

  def test_get_event
    response = RestClient.get 'localhost:4567/event/test/test'
    assert_equal(200, response.code.to_i)
  end

  def test_get_client
    response = RestClient.get 'localhost:4567/client/test'
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

  def test_delete_client
    response = RestClient.delete 'localhost:4567/client/test'
    assert_equal(204, response.code.to_i)
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

  def test_create_stash
    response = RestClient.post 'localhost:4567/stash/tester', :data => '{"key": "value"}'
    assert_equal(201, response.code.to_i)
  end

  def test_get_stash
    response = RestClient.get 'localhost:4567/stash/test/test'
    assert_equal(200, response.code.to_i)
  end

  def test_delete_stash
    response = RestClient.delete 'localhost:4567/stash/test/test'
    assert_equal(204, response.code.to_i)
  end
end

MiniTest::Unit.after_tests do
  Process.kill('KILL', api)
end
