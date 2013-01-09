class TestSensuAPI < TestCase
  def test_get_info
    Sensu::API.run_test(@options) do
      api_request('/info') do |http, body|
        assert_equal(200, http.response_header.status)
        assert_equal(Sensu::VERSION, body[:sensu][:version])
        assert_equal('ok', body[:health][:redis])
        assert_equal('ok', body[:health][:rabbitmq])
        done
      end
    end
  end

  def test_get_events
    Sensu::API.run_test(@options) do
      api_request('/events') do |http, body|
        assert_equal(200, http.response_header.status)
        assert(body.is_a?(Array))
        assert_block "Response didn't contain the test event" do
          body.any? do |event|
            if event[:client] == @settings[:client][:name]
              event[:check] == 'test'
            end
          end
        end
        done
      end
    end
  end

  def test_get_client_events
    Sensu::API.run_test(@options) do
      api_request('/events/' + @settings[:client][:name]) do |http, body|
        assert_equal(200, http.response_header.status)
        assert(body.is_a?(Array))
        assert_block "Response didn't contain the test event" do
          body.any? do |event|
            event[:check] == 'test'
          end
        end
        done
      end
    end
  end

  def test_get_clients
    Sensu::API.run_test(@options) do
      api_request('/clients') do |http, body|
        assert_equal(200, http.response_header.status)
        assert(body.is_a?(Array))
        assert_block "Response didn't contain the test client" do
          body.any? do |client|
            client[:name] == @settings[:client][:name]
          end
        end
        done
      end
    end
  end

  def test_get_checks
    Sensu::API.run_test(@options) do
      api_request('/checks') do |http, body|
        assert_equal(200, http.response_header.status)
        assert_equal(@settings.checks, body)
        done
      end
    end
  end

  def test_get_event
    Sensu::API.run_test(@options) do
      api_request('/event/' + @settings[:client][:name] + '/test') do |http, body|
        assert_equal(200, http.response_header.status)
        expected = {
          :client => @settings[:client][:name],
          :check => 'test',
          :output => 'CRITICAL',
          :status => 2,
          :flapping => false,
          :occurrences => 1
        }
        assert_equal(expected, sanitize_keys(body))
        done
      end
    end
  end

  def test_delete_event
    Sensu::API.run_test(@options) do
      api_request('/event/' + @settings[:client][:name] + '/test', :delete) do |http, body|
        assert_equal(202, http.response_header.status)
        done
      end
    end
  end

  def test_resolve_event
    Sensu::API.run_test(@options) do
      options = {
        :body => {
          :client => @settings[:client][:name],
          :check => 'test'
        }.to_json
      }
      api_request('/resolve', :post, options) do |http, body|
        assert_equal(202, http.response_header.status)
        done
      end
    end
  end

  def test_resolve_nonexistent_event
    Sensu::API.run_test(@options) do
      options = {
        :body => {
          :client => @settings[:client][:name],
          :check => 'nonexistent'
        }.to_json
      }
      api_request('/resolve', :post, options) do |http, body|
        assert_equal(404, http.response_header.status)
        done
      end
    end
  end

  def test_resolve_event_malformed
    Sensu::API.run_test(@options) do
      options = {
        :body => 'malformed'
      }
      api_request('/resolve', :post, options) do |http, body|
        assert_equal(400, http.response_header.status)
        done
      end
    end
  end

  def test_resolve_event_missing_data
    Sensu::API.run_test(@options) do
      options = {
        :body => {
          :client => @settings[:client][:name]
        }.to_json
      }
      api_request('/resolve', :post, options) do |http, body|
        assert_equal(400, http.response_header.status)
        done
      end
    end
  end

  def test_get_client
    Sensu::API.run_test(@options) do
      api_request('/client/' + @settings[:client][:name]) do |http, body|
        assert_equal(200, http.response_header.status)
        assert_equal(@settings[:client], sanitize_keys(body))
        done
      end
    end
  end

  def test_get_nonexistent_client
    Sensu::API.run_test(@options) do
      api_request('/client/nonexistent') do |http, body|
        assert_equal(404, http.response_header.status)
        done
      end
    end
  end

  def test_delete_client
    Sensu::API.run_test(@options) do
      api_request('/client/' + @settings[:client][:name], :delete) do |http, body|
        assert_equal(202, http.response_header.status)
        done
      end
    end
  end

  def test_delete_nonexistent_client
    Sensu::API.run_test(@options) do
      api_request('/client/nonexistent', :delete) do |http, body|
        assert_equal(202, http.response_header.status)
        done
      end
    end
  end

  def test_get_check
    Sensu::API.run_test(@options) do
      api_request('/check/tokens') do |http, body|
        assert_equal(200, http.response_header.status)
        expected = @settings[:checks][:tokens].merge(:name => 'tokens')
        assert_equal(expected, body)
        done
      end
    end
  end

  def test_get_nonexistent_check
    Sensu::API.run_test(@options) do
      api_request('/check/nonexistent') do |http, body|
        assert_equal(404, http.response_header.status)
        done
      end
    end
  end

  def test_check_request
    Sensu::API.run_test(@options) do
      options = {
        :body => {
          :check => 'tokens',
          :subscribers => [
            'test'
          ]
        }.to_json
      }
      api_request('/request', :post, options) do |http, body|
        assert_equal(201, http.response_header.status)
        done
      end
    end
  end

  def test_check_request_malformed
    Sensu::API.run_test(@options) do
      options = {
        :body => {
          :check => 'tokens',
          :subscribers => 'malformed'
        }.to_json
      }
      api_request('/request', :post, options) do |http, body|
        assert_equal(400, http.response_header.status)
        done
      end
    end
  end

  def test_check_request_missing_data
    Sensu::API.run_test(@options) do
      options = {
        :body => {
          :subscribers => [
            'test'
          ]
        }.to_json
      }
      api_request('/request', :post, options) do |http, body|
        assert_equal(400, http.response_header.status)
        done
      end
    end
  end

  def test_check_request_missing_check
    Sensu::API.run_test(@options) do
      options = {
        :body => {
          :check => 'nonexistent'
        }.to_json
      }
      api_request('/request', :post, options) do |http, body|
        assert_equal(404, http.response_header.status)
        done
      end
    end
  end

  def test_create_stash
    Sensu::API.run_test(@options) do
      options = {
        :body => {
          :key => 'value'
        }.to_json
      }
      api_request('/stash/tester', :post, options) do |http, body|
        assert_equal(201, http.response_header.status)
        done
      end
    end
  end

  def test_get_stash
    Sensu::API.run_test(@options) do
      api_request('/stash/test/test') do |http, body|
        assert_equal(200, http.response_header.status)
        expected = {:key => 'value'}
        assert_equal(expected, body)
        done
      end
    end
  end

  def test_get_stashes
    Sensu::API.run_test(@options) do
      api_request('/stashes') do |http, body|
        assert_equal(200, http.response_header.status)
        assert(body.is_a?(Array))
        assert_block "Response didn't contain a test stash" do
          body.any? do |path, stash|
            ['test/test', 'tester'].include?(path)
          end
        end
        done
      end
    end
  end

  def test_multi_get_stashes
    Sensu::API.run_test(@options) do
      options = {
        :body => [
          'test/test',
          'tester'
        ].to_json
      }
      api_request('/stashes', :post, options) do |http, body|
        assert_equal(200, http.response_header.status)
        assert(body.is_a?(Hash))
        assert_block "Response didn't contain a test stash" do
          body.any? do |path, stash|
            [:'test/test', :tester].include?(path)
          end
        end
        done
      end
    end
  end

  def test_delete_stash
    Sensu::API.run_test(@options) do
      api_request('/stash/test/test', :delete) do |http, body|
        assert_equal(204, http.response_header.status)
        done
      end
    end
  end
end
