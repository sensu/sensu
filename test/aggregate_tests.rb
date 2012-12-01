class TestSensuAggregate < TestCase
  def test_check_aggregate
    server = Sensu::Server.new(@options)
    server.setup_redis
    server.redis.flushall.callback do
      5.times do |seconds|
        issued = Time.now.to_i + seconds
        %w[foo bar].each_with_index do |client_name, index|
          result = {
            :client => client_name,
            :check => {
              :name => 'check_http',
              :issued => issued,
              :output => 'exited with status: ' + index.to_s,
              :status => index,
              :aggregate => true
            }
          }
          server.aggregate_result(result)
        end
      end
      EM::Timer.new(3) do
        Sensu::API.run_test(@options) do
          api_request('/aggregates') do |http, body|
            assert_equal(200, http.response_header.status)
            assert(body.is_a?(Array))
            assert(body.first.is_a?(Hash))
            assert_equal('check_http', body.first[:check])
            assert(body.first[:issued].is_a?(Array))
            api_request('/aggregates/check_http?limit=2') do |http, body|
              assert(body.is_a?(Array))
              assert_equal(2, body.size)
              check_issued = body.first
              uri = '/aggregates/check_http/' + check_issued + '?results=true&summarize=output'
              api_request(uri) do |http, body|
                assert_equal(200, http.response_header.status)
                assert(body.is_a?(Hash))
                assert_equal(2, body[:total])
                assert_equal(1, body[:ok])
                assert_equal(1, body[:warning])
                assert(body[:outputs].is_a?(Hash))
                assert_equal(2, body[:outputs].size)
                assert(body[:results].is_a?(Array))
                assert_equal(2, body[:results].size)
                done
              end
            end
          end
        end
      end
    end
  end

  def test_nonexistent_aggregate
    Sensu::API.run_test(@options) do
      api_request('/aggregates/nonexistent/1348376207') do |http, body|
        assert_equal(404, http.response_header.status)
        done
      end
    end
  end
end
