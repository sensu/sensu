class TestSensuFlapDetection < TestCase
  def test_flap_detection
    server, client = base_server_client
    server.redis.flushall.callback do
      26.times do |index|
        check = {
          :name => 'flapper',
          :issued => Time.now.to_i,
          :output => 'foobar',
          :status => index % 2,
          :low_flap_threshold => 5,
          :high_flap_threshold => 20
        }
        client.publish_result(check)
      end
      EM::Timer.new(3) do
        server.redis.hget('events:' + @settings[:client][:name], 'flapper').callback do |event_json|
          assert(event_json)
          event = JSON.parse(event_json, :symbolize_names => true)
          assert(event[:flapping])
          done
        end
      end
    end
  end
end
