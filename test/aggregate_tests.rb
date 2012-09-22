class TestSensuAggregate < TestCase
  def setup
    super
    @api_uri = 'http://' + @settings[:api][:host] + ':' + @settings[:api][:port].to_s
    @request_options = {
      :head => {
        :authorization => [
          @settings[:api][:user],
          @settings[:api][:password]
        ]
      }
    }
  end

  def test_check_aggregate
    server = Sensu::Server.new(@options)
    server.setup_redis
    result_template = {
      :check => {
        :name => "check_http",
        :issued => Time.now.to_i,
        :aggregate => true
      }
    }
    server.redis.flushall.callback do
      %w[foo bar].each_with_index do |client_name, index|
        result = result_template
        result[:client] = client_name
        result[:check][:output] = 'exited with status: ' + index.to_s
        result[:check][:status] = index
        server.store_result(result)
      end
      EM::Timer.new(2) do
        Sensu::API.run_test(@options) do
          http = EM::HttpRequest.new(@api_uri + '/aggregates').get(@request_options)
          http.callback do
            assert_equal(200, http.response_header.status)
            aggregates = JSON.parse(http.response, :symbolize_names => true)
            assert(aggregates.is_a?(Hash))
            done
          end
        end
      end
    end
  end
end
