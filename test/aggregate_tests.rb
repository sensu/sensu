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
    server.redis.flushall.callback do
      %w[foo bar].each_with_index do |client_name, index|
        result = {
          :client => client_name,
          :check => {
            :name => 'check_http',
            :issued => Time.now.to_i,
            :output => 'exited with status: ' + index.to_s,
            :status => index,
            :aggregate => true
          }
        }
        server.store_result(result)
      end
      EM::Timer.new(3) do
        Sensu::API.run_test(@options) do
          http = EM::HttpRequest.new(@api_uri + '/aggregates').get(@request_options)
          http.callback do
            assert_equal(200, http.response_header.status)
            aggregates = JSON.parse(http.response, :symbolize_names => true)
            assert(aggregates.is_a?(Array))
            assert(aggregates.first.is_a?(Hash))
            assert_equal('check_http', aggregates.first[:check])
            assert(aggregates.first[:issued].is_a?(Array))
            check_issued = aggregates.first[:issued].first
            url = @api_uri + '/aggregates/check_http/' + check_issued + '?summarize=output,status'
            http = EM::HttpRequest.new(url).get(@request_options)
            http.callback do
              assert_equal(200, http.response_header.status)
              aggregate = JSON.parse(http.response, :symbolize_names => true)
              assert(aggregate.is_a?(Hash))
              assert_equal(2, aggregate[:TOTAL])
              assert_equal(1, aggregate[:OK])
              assert_equal(1, aggregate[:WARNING])
              done
            end
          end
        end
      end
    end
  end
end
