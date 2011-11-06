class TestSensuAPI < Test::Unit::TestCase
  include EventMachine::Test

  def setup
    @options = {:config_file => File.join(File.dirname(__FILE__), 'config.json')}
    config = Sensu::Config.new(@options)
    @settings = config.settings
    Sensu::API.test(@options)
  end

  def test_get_clients
    http = EventMachine::Protocols::HttpClient.request(
      :host => 'localhost',
      :port => 4567,
      :request => '/clients'
    )
    http.callback do |response|
      assert_equal(200, response[:status])
      clients = JSON.parse(response[:content])
      assert(clients.is_a?(Array))
      contains_test_client = false
      assert_block "Response didn't contain the test client" do
        clients.each do |client|
          contains_test_client = true if client['name'] == @settings.client.name
        end
        contains_test_client
      end
      done
    end
  end

  def test_get_events
    http = EventMachine::Protocols::HttpClient.request(
      :host => 'localhost',
      :port => 4567,
      :request => '/events'
    )
    http.callback do |response|
      assert_equal(200, response[:status])
      events = JSON.parse(response[:content])
      assert(events.is_a?(Hash))
      contains_test_event = false
      assert_block "Response didn't contain the test event" do
        events.each do |client, events|
          if client == @settings.client.name
            events.each do |check, event|
              contains_test_event = true if check == 'test'
            end
          end
        end
        contains_test_event
      end
      done
    end
  end

  def test_get_event
    http = EventMachine::Protocols::HttpClient.request(
      :host => 'localhost',
      :port => 4567,
      :request => '/event/' + @settings.client.name + '/test'
    )
    http.callback do |response|
      assert_equal(200, response[:status])
      expected = {
        :status => 2,
        :output => 'CRITICAL',
        :flapping => false,
        :occurrences => 1
      }
      assert_equal(expected, JSON.parse(response[:content]).symbolize_keys)
      done
    end
  end

  def test_get_client
    http = EventMachine::Protocols::HttpClient.request(
      :host => 'localhost',
      :port => 4567,
      :request => '/client/' + @settings.client.name
    )
    http.callback do |response|
      assert_equal(200, response[:status])
      assert_equal(@settings.client, JSON.parse(response[:content]).reject { |key, value| key == 'timestamp' })
      done
    end
  end

  def test_get_nonexistent_client
    http = EventMachine::Protocols::HttpClient.request(
      :host => 'localhost',
      :port => 4567,
      :request => '/client/nonexistent'
    )
    http.callback do |response|
      assert_equal(404, response[:status])
      done
    end
  end

  def test_delete_client
    http = EventMachine::Protocols::HttpClient.request(
      :host => 'localhost',
      :port => 4567,
      :verb => 'DELETE',
      :request => '/client/' + @settings.client.name
    )
    http.callback do |response|
      assert_equal(204, response[:status])
      done
    end
  end

  def test_delete_nonexistent_client
    http = EventMachine::Protocols::HttpClient.request(
      :host => 'localhost',
      :port => 4567,
      :verb => 'DELETE',
      :request => '/client/nonexistent'
    )
    http.callback do |response|
      assert_equal(404, response[:status])
      done
    end
  end

  def test_create_stash
    http = EventMachine::Protocols::HttpClient.request(
      :host => 'localhost',
      :port => 4567,
      :verb => 'POST',
      :request => '/stash/tester',
      :content => '{"key": "value"}'
    )
    http.callback do |response|
      assert_equal(201, response[:status])
      done
    end
  end

  def test_get_stash
    http = EventMachine::Protocols::HttpClient.request(
      :host => 'localhost',
      :port => 4567,
      :request => '/stash/test/test'
    )
    http.callback do |response|
      assert_equal(200, response[:status])
      done
    end
  end

  def test_get_stashes
    http = EventMachine::Protocols::HttpClient.request(
      :host => 'localhost',
      :port => 4567,
      :verb => 'POST',
      :request => '/stashes',
      :content => '["test/test", "tester"]'
    )
    http.callback do |response|
      stashes = JSON.parse(response[:content])
      assert(stashes.is_a?(Hash))
      contains_test_stash = false
      assert_block "Response didn't contain a test stash" do
        stashes.each do |path, stash|
          contains_test_stash = true if ['test/test', 'tester'].include?(path)
        end
        contains_test_stash
      end
      done
    end
  end

  def test_delete_stash
    http = EventMachine::Protocols::HttpClient.request(
      :host => 'localhost',
      :port => 4567,
      :verb => 'DELETE',
      :request => '/stash/test/test'
    )
    http.callback do |response|
      assert_equal(204, response[:status])
      done
    end
  end
end
