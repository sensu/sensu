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
          amq.direct("keepalives").publish(MultiJson.dump(keepalive))
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
          result = result_template
          result[:client] = client_name
          result[:check][:status] = index
          @server.aggregate_check_result(result)
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
end
