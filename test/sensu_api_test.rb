class TestSensuAPI < MiniTest::Unit::TestCase
  def setup
    RestClient.post 'localhost:4567/test', nil
  end

  def test_get_clients
    response = RestClient.get 'localhost:4567/clients'
    assert_block "Unexpected response body" do
      JSON.parse(response.body).is_a?(Array)
    end
    contains_test_client = false
    assert_block "Response didn't contain the test client" do
      JSON.parse(response.body).each do |client|
        contains_test_client = true if client['name'] == 'test'
      end
      contains_test_client
    end
    assert_equal(200, response.code.to_i)
  end

  def test_get_events
    response = RestClient.get 'localhost:4567/events'
    assert_block "Unexpected response body" do
      JSON.parse(response.body).is_a?(Hash)
    end
    contains_test_event = false
    assert_block "Response didn't contain the test event" do
      JSON.parse(response.body).each do |client, events|
        if client == 'test'
          events.each do |check, event|
            contains_test_event = true if check == 'test'
          end
        end
      end
      contains_test_event
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
    response = RestClient.post 'localhost:4567/stash/tester', '{"key": "value"}'
    assert_equal(201, response.code.to_i)
  end

  def test_get_stash
    response = RestClient.get 'localhost:4567/stash/test/test'
    assert_equal(200, response.code.to_i)
  end

  def test_get_stashes
    response = RestClient.post 'localhost:4567/stashes', '["test/test", "tester"]'
    assert_equal(200, response.code.to_i)
    contains_test_stash = false
    assert_block "Response didn't contain a test stash" do
      JSON.parse(response.body).each do |path, stash|
        contains_test_stash = true if ['test/test', 'tester'].include?(path)
      end
      contains_test_stash
    end
  end

  def test_delete_stash
    response = RestClient.delete 'localhost:4567/stash/test/test'
    assert_equal(204, response.code.to_i)
  end
end
