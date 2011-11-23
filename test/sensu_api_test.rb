class TestSensuAPI < Test::Unit::TestCase
  include EventMachine::Test

  def setup
    @options = {:config_file => File.join(File.dirname(__FILE__), 'config.json')}
    config = Sensu::Config.new(@options)
    @settings = config.settings
    @api = 'http://' + @settings.api.host + ':' + @settings.api.port.to_s
    Sensu::API.test(@options)
  end

  def test_get_clients
    EM.add_timer(1) do
      http = EM::HttpRequest.new(@api + '/clients').get
      http.callback do
        assert_equal(200, http.response_header.status)
        clients = JSON.parse(http.response)
        assert(clients.is_a?(Array))
        assert_block "Response didn't contain the test client" do
          contains_test_client = false
          clients.each do |client|
            contains_test_client = true if client['name'] == @settings.client.name
          end
          contains_test_client
        end
        done
      end
    end
  end

  def test_get_events
    EM.add_timer(1) do
      http = EM::HttpRequest.new(@api + '/events').get
      http.callback do
        assert_equal(200, http.response_header.status)
        events = JSON.parse(http.response)
        assert(events.is_a?(Hash))
        assert_block "Response didn't contain the test event" do
          contains_test_event = false
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
  end

  def test_get_event
    EM.add_timer(1) do
      http = EM::HttpRequest.new(@api + '/event/' + @settings.client.name + '/test').get
      http.callback do
        assert_equal(200, http.response_header.status)
        expected = {
          :status => 2,
          :output => 'CRITICAL',
          :flapping => false,
          :occurrences => 1
        }
        assert_equal(expected, JSON.parse(http.response).symbolize_keys)
        done
      end
    end
  end

  def test_resolve_event
    EM.add_timer(1) do
      options = {
        :body => '{"client": "' + @settings.client.name + '", "check": "test"}'
      }
      http = EM::HttpRequest.new(@api + '/event/resolve').post options
      http.callback do
        assert_equal(201, http.response_header.status)
        done
      end
    end
  end

  def test_resolve_nonexistent_event
    EM.add_timer(1) do
      options = {
        :body => '{"client": "' + @settings.client.name + '", "check": "nonexistent"}'
      }
      http = EM::HttpRequest.new(@api + '/event/resolve').post options
      http.callback do
        assert_equal(404, http.response_header.status)
        done
      end
    end
  end

  def test_resolve_event_malformed
    EM.add_timer(1) do
      options = {
        :body => 'malformed'
      }
      http = EM::HttpRequest.new(@api + '/event/resolve').post options
      http.callback do
        assert_equal(400, http.response_header.status)
        done
      end
    end
  end

  def test_get_client
    EM.add_timer(1) do
      http = EM::HttpRequest.new(@api + '/client/' + @settings.client.name).get
      http.callback do
        assert_equal(200, http.response_header.status)
        assert_equal(@settings.client, JSON.parse(http.response).reject { |key, value| key == 'timestamp' })
        done
      end
    end
  end

  def test_get_nonexistent_client
    EM.add_timer(1) do
      http = EM::HttpRequest.new(@api + '/client/nonexistent').get
      http.callback do
        assert_equal(404, http.response_header.status)
        done
      end
    end
  end

  def test_delete_client
    EM.add_timer(1) do
      http = EM::HttpRequest.new(@api + '/client/' + @settings.client.name).delete
      http.callback do
        assert_equal(204, http.response_header.status)
        done
      end
    end
  end

  def test_delete_nonexistent_client
    EM.add_timer(1) do
      http = EM::HttpRequest.new(@api + '/client/nonexistent').delete
      http.callback do
        assert_equal(404, http.response_header.status)
        done
      end
    end
  end

  def test_create_stash
    EM.add_timer(1) do
      options = {
        :body => '{"key": "value"}'
      }
      http = EM::HttpRequest.new(@api + '/stash/tester').post options
      http.callback do
        assert_equal(201, http.response_header.status)
        done
      end
    end
  end

  def test_get_stash
    EM.add_timer(1) do
      http = EM::HttpRequest.new(@api + '/stash/test/test').get
      http.callback do |response|
        assert_equal(200, http.response_header.status)
        done
      end
    end
  end

  def test_get_stashes
    EM.add_timer(1) do
      http = EM::HttpRequest.new(@api + '/stashes').get
      http.callback do
        assert_equal(200, http.response_header.status)
        stashes = JSON.parse(http.response)
        assert(stashes.is_a?(Array))
        assert_block "Response didn't contain a test stash" do
          contains_test_stash = false
          stashes.each do |path, stash|
            contains_test_stash = true if ['test/test', 'tester'].include?(path)
          end
          contains_test_stash
        end
        done
      end
    end
  end

  def test_multi_get_stashes
    EM.add_timer(1) do
      options = {
        :body => '["test/test", "tester"]'
      }
      http = EM::HttpRequest.new(@api + '/stashes').post options
      http.callback do
        assert_equal(200, http.response_header.status)
        stashes = JSON.parse(http.response)
        assert(stashes.is_a?(Hash))
        assert_block "Response didn't contain a test stash" do
          contains_test_stash = false
          stashes.each do |path, stash|
            contains_test_stash = true if ['test/test', 'tester'].include?(path)
          end
          contains_test_stash
        end
        done
      end
    end
  end

  def test_delete_stash
    EM.add_timer(1) do
      http = EM::HttpRequest.new(@api + '/stash/test/test').delete
      http.callback do |response|
        assert_equal(204, http.response_header.status)
        done
      end
    end
  end
end
