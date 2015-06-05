require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/server/process"

describe "Sensu::Server::Process" do
  include Helpers

  before do
    @server = Sensu::Server::Process.new(options)
    @event = event_template
  end

  it "can connect to redis" do
    async_wrapper do
      @server.setup_redis
      timer(0.5) do
        async_done
      end
    end
  end

  it "can connect to rabbitmq" do
    async_wrapper do
      @server.setup_transport
      timer(0.5) do
        async_done
      end
    end
  end

  it "can consume client keepalives" do
    async_wrapper do
      @server.setup_redis
      @server.setup_transport
      @server.setup_keepalives
      keepalive = client_template
      keepalive[:timestamp] = epoch
      redis.flushdb do
        timer(1) do
          transport.publish(:direct, "keepalives", MultiJson.dump(keepalive))
          timer(1) do
            redis.sismember("clients", "i-424242") do |exists|
              expect(exists).to be(true)
              redis.get("client:i-424242") do |client_json|
                client = MultiJson.load(client_json)
                expect(client).to eq(keepalive)
                async_done
              end
            end
          end
        end
      end
    end
  end

  it "can derive handlers from a handler list containing a nested set" do
    handler_list = ["nested_set_one"]
    handlers = @server.derive_handlers(handler_list)
    expect(handlers.size).to eq(2)
    expect(handlers.first).to be_an_instance_of(Sensu::Extension::Debug)
    expected = {
      :name => "file",
      :type => "pipe",
      :command => "cat > /tmp/sensu_event"
    }
    expect(handlers.last).to eq(expected)
  end

  it "can aggregate check results" do
    async_wrapper do
      @server.setup_redis
      timestamp = epoch
      clients = ["foo", "bar", "baz", "qux"]
      redis.flushdb do
        clients.each_with_index do |client_name, index|
          client = client_template
          client[:name] = client_name
          check = check_template
          check[:issued] = timestamp
          check[:executed] = timestamp + index
          check[:status] = index
          @server.aggregate_check_result(client, check)
        end
        timer(2) do
          result_set = "test:#{timestamp}"
          redis.sismember("aggregates", "test") do |exists|
            expect(exists).to be(true)
            redis.sismember("aggregates:test", timestamp.to_s) do |exists|
              expect(exists).to be(true)
              redis.hgetall("aggregate:#{result_set}") do |aggregate|
                expect(aggregate["total"]).to eq("4")
                expect(aggregate["ok"]).to eq("1")
                expect(aggregate["warning"]).to eq("1")
                expect(aggregate["critical"]).to eq("1")
                expect(aggregate["unknown"]).to eq("1")
                redis.hgetall("aggregation:#{result_set}") do |aggregation|
                  clients.each do |client_name|
                    expect(aggregation).to include(client_name)
                  end
                  async_done
                end
              end
            end
          end
        end
      end
    end
  end

  it "can process results with flap detection" do
    async_wrapper do
      @server.setup_redis
      redis.flushdb do
        client = client_template
        redis.set("client:i-424242", MultiJson.dump(client)) do
          26.times do |index|
            result = result_template
            result[:check][:low_flap_threshold] = 5
            result[:check][:high_flap_threshold] = 20
            result[:check][:status] = index % 2
            @server.process_check_result(result)
          end
          timer(1) do
            redis.llen("history:i-424242:test") do |length|
              expect(length).to eq(21)
              redis.hget("events:i-424242", "test") do |event_json|
                event = MultiJson.load(event_json)
                expect(event[:action]).to eq("flapping")
                expect(event[:occurrences]).to be_within(2).of(1)
                26.times do |index|
                  result = result_template
                  result[:check][:low_flap_threshold] = 5
                  result[:check][:high_flap_threshold] = 20
                  result[:check][:status] = 0
                  @server.process_check_result(result)
                end
                timer(1) do
                  redis.hexists("events:i-424242", "test") do |exists|
                    expect(exists).to be(false)
                    async_done
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  it "can consume results" do
    async_wrapper do
      @server.setup_transport
      @server.setup_redis
      @server.setup_results
      redis.flushdb do
        timer(1) do
          client = client_template
          redis.set("client:i-424242", MultiJson.dump(client)) do
            result = result_template
            transport.publish(:direct, "results", MultiJson.dump(result))
            transport.publish(:direct, "results", MultiJson.dump(result))
            timer(3) do
              redis.sismember("result:i-424242", "test") do |is_member|
                expect(is_member).to be(true)
                redis.get("result:i-424242:test") do |result_json|
                  result = MultiJson.load(result_json)
                  expect(result[:output]).to eq("WARNING")
                  timer(2) do
                    redis.hget("events:i-424242", "test") do |event_json|
                      event = MultiJson.load(event_json)
                      expect(event[:id]).to be_kind_of(String)
                      expect(event[:check][:status]).to eq(1)
                      expect(event[:occurrences]).to eq(2)
                      timer(3) do
                        begin
                          event_file = IO.read("/tmp/sensu-event.json")
                          parsed_event_file = MultiJson.load(event_file)
                          raise unless parsed_event_file[:occurrences] == 2
                        rescue
                          retry
                        end
                        expect(parsed_event_file).to eq(event)
                        async_done
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  it "can dynamically create a client for a check source" do
    async_wrapper do
      @server.setup_transport
      @server.setup_redis
      @server.setup_results
      redis.flushdb do
        timer(1) do
          result = result_template
          result[:check][:source] = "i-888888"
          result[:check][:handler] = "debug"
          transport.publish(:direct, "results", MultiJson.dump(result))
          timer(3) do
            redis.sismember("clients", "i-888888") do |exists|
              expect(exists).to be(true)
              redis.get("client:i-888888") do |client_json|
                client = MultiJson.load(client_json)
                expect(client[:keepalives]).to be(false)
                expect(client[:version]).to eq(Sensu::VERSION)
                redis.hget("events:i-888888", "test") do |event_json|
                  event = MultiJson.load(event_json)
                  expect(event[:client][:address]).to eq("unknown")
                  async_done
                end
              end
            end
          end
        end
      end
    end
  end

  it "can publish check requests" do
    async_wrapper do
      transport.subscribe(:fanout, "test") do |_, payload|
        check_request = MultiJson.load(payload)
        expect(check_request[:name]).to eq("test")
        expect(check_request[:command]).to eq("echo WARNING && exit 1")
        expect(check_request[:source]).to eq("switch-x")
        expect(check_request[:issued]).to be_within(10).of(epoch)
        async_done
      end
      timer(0.5) do
        @server.setup_transport
        check = check_template
        check[:subscribers] = ["test"]
        check[:source] = "switch-x"
        @server.publish_check_request(check)
      end
    end
  end

  it "can publish check requests to round-robin subscriptions" do
    async_wrapper do
      transport.subscribe(:direct, "roundrobin:test") do |_, payload|
        check_request = MultiJson.load(payload)
        expect(check_request[:name]).to eq("test")
        expect(check_request[:command]).to eq("echo WARNING && exit 1")
        expect(check_request[:issued]).to be_within(10).of(epoch)
        async_done
      end
      timer(0.5) do
        @server.setup_transport
        check = check_template
        check[:subscribers] = ["roundrobin:test"]
        @server.publish_check_request(check)
      end
    end
  end

  it "can calculate a check execution splay interval" do
    allow(Time).to receive(:now).and_return("1414213569.032")
    check = check_template
    check[:interval] = 60
    expect(@server.calculate_check_execution_splay(check)).to eq(17.601)
    check[:interval] = 3600
    expect(@server.calculate_check_execution_splay(check)).to eq(3497.601)
  end

  it "can schedule check request publishing" do
    async_wrapper do
      expected = ["tokens", "merger", "sensu_cpu_time", "source"]
      transport.subscribe(:fanout, "test") do |_, payload|
        check_request = MultiJson.load(payload)
        expect(check_request[:issued]).to be_within(10).of(epoch)
        expect(expected.delete(check_request[:name])).not_to be_nil
        async_done if expected.empty?
      end
      timer(0.5) do
        @server.setup_transport
        @server.setup_check_request_publisher
      end
    end
  end

  it "can send a check result" do
    async_wrapper do
      result_queue do |payload|
        result = MultiJson.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:name]).to eq("test")
        async_done
      end
      timer(0.5) do
        @server.setup_transport
        client = client_template
        check = result_template[:check]
        @server.publish_check_result(client[:name], check)
      end
    end
  end

  it "can determine stale clients and create the appropriate events" do
    async_wrapper do
      @server.setup_redis
      @server.setup_transport
      @server.setup_results
      client1 = client_template
      client1[:name] = "foo"
      client1[:timestamp] = epoch - 60
      client1[:keepalive][:handler] = "debug"
      client2 = client_template
      client2[:name] = "bar"
      client2[:timestamp] = epoch - 120
      client3 = client_template
      client3[:name] = "qux"
      client3[:keepalives] = false
      client3[:timestamp] = epoch - 1800
      redis.set("client:foo", MultiJson.dump(client1)) do
        redis.sadd("clients", "foo") do
          redis.set("client:bar", MultiJson.dump(client2)) do
            redis.sadd("clients", "bar") do
              redis.set("client:qux", MultiJson.dump(client3)) do
                redis.sadd("clients", "qux") do
                  @server.determine_stale_clients
                  timer(1) do
                    redis.hget("events:foo", "keepalive") do |event_json|
                      event = MultiJson.load(event_json)
                      expect(event[:check][:status]).to eq(1)
                      expect(event[:check][:handler]).to eq("debug")
                      redis.hget("events:bar", "keepalive") do |event_json|
                        event = MultiJson.load(event_json)
                        expect(event[:check][:status]).to eq(2)
                        expect(event[:check][:handler]).to eq("keepalive")
                        redis.hget("events:qux", "keepalive") do |event_json|
                          expect(event_json).to be(nil)
                          async_done
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  it "can determine stale check results" do
    async_wrapper do
      @server.setup_redis
      @server.setup_transport
      @server.setup_results
      redis.flushdb do
        timer(1) do
          client = client_template
          redis.set("client:i-424242", MultiJson.dump(client)) do
            redis.sadd("clients", "i-424242") do
              result = result_template
              result[:check][:status] = 0
              result[:check][:executed] = epoch - 30
              transport.publish(:direct, "results", MultiJson.dump(result))
              result[:check][:name] = "foo"
              result[:check][:ttl] = 30
              transport.publish(:direct, "results", MultiJson.dump(result))
              result[:check][:name] = "bar"
              result[:check][:ttl] = 60
              transport.publish(:direct, "results", MultiJson.dump(result))
              timer(2) do
                @server.determine_stale_check_results
                timer(2) do
                  redis.hgetall("events:i-424242") do |events|
                    expect(events.size).to eq(1)
                    event = MultiJson.load(events["foo"])
                    expect(event[:check][:output]).to match(/Last check execution was 3[0-9] seconds ago/)
                    expect(event[:check][:status]).to eq(1)
                    async_done
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  it "can prune aggregations" do
    async_wrapper do
      @server.setup_redis
      redis.flushdb do
        client = client_template
        redis.set("client:i-424242", MultiJson.dump(client)) do
          timestamp = epoch - 26
          26.times do |index|
            check = check_template
            check[:issued] = timestamp + index
            check[:status] = index
            @server.aggregate_check_result(client, check)
          end
          timer(1) do
            redis.smembers("aggregates:test") do |aggregates|
              aggregates.sort!
              expect(aggregates.size).to eq(26)
              oldest = aggregates.shift
              @server.prune_check_result_aggregations
              timer(1) do
                redis.smembers("aggregates:test") do |aggregates|
                  expect(aggregates.size).to eq(20)
                  expect(aggregates).not_to include(oldest)
                  result_set = "test:#{oldest}"
                  redis.exists("aggregate:#{result_set}") do |exists|
                    expect(exists).to be(false)
                    redis.exists("aggregation:#{result_set}") do |exists|
                      expect(exists).to be(false)
                      async_done
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  it "can be the leader and resign" do
    async_wrapper do
      @server.setup_redis
      @server.setup_transport
      redis.flushdb do
        @server.request_leader_election
        timer(1) do
          expect(@server.is_leader).to be(true)
          @server.resign_as_leader
          expect(@server.is_leader).to be(false)
          async_done
        end
      end
    end
  end

  it "can be the only leader" do
    async_wrapper do
      server1 = @server.clone
      server2 = @server.clone
      server1.setup_redis
      server2.setup_redis
      server1.setup_transport
      server2.setup_transport
      redis.flushdb do
        lock_timestamp = (Time.now.to_f * 1000).to_i - 60000
        redis.set("lock:leader", lock_timestamp) do
          server1.setup_leader_monitor
          server2.setup_leader_monitor
          timer(3) do
            expect([server1.is_leader, server2.is_leader].uniq.size).to eq(2)
            async_done
          end
        end
      end
    end
  end
end
