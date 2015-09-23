require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/api/process"
require "sensu/server/process"

describe "Sensu::API::Process" do
  include Helpers

  before do
    async_wrapper do
      client = client_template
      client[:timestamp] = epoch
      @event = event_template
      @check = check_template
      redis.flushdb do
        redis.set("client:i-424242", MultiJson.dump(client)) do
          redis.sadd("clients", "i-424242") do
            redis.hset("events:i-424242", "test", MultiJson.dump(@event)) do
              redis.set("result:i-424242:test", MultiJson.dump(@check)) do
                redis.set("stash:test/test", MultiJson.dump({:key => "value"})) do
                  redis.expire("stash:test/test", 3600) do
                    redis.sadd("stashes", "test/test") do
                      redis.sadd("result:i-424242", "test") do
                        redis.rpush("history:i-424242:test", 0) do
                          @redis = nil
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

  it "can handle integer parameters" do
    api = Sensu::API::Process.new!
    expect(api.integer_parameter("42")).to eq(42)
    expect(api.integer_parameter("abc")).to eq(nil)
    expect(api.integer_parameter("42\nabc")).to eq(nil)
  end

  it "can provide basic version and health information" do
    api_test do
      api_request("/info") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body[:sensu][:version]).to eq(Sensu::VERSION)
        expect(body[:redis][:connected]).to be(true)
        expect(body[:transport][:connected]).to be(true)
        expect(body[:transport][:keepalives][:messages]).to be_kind_of(Integer)
        expect(body[:transport][:keepalives][:consumers]).to be_kind_of(Integer)
        expect(body[:transport][:results][:messages]).to be_kind_of(Integer)
        expect(body[:transport][:results][:consumers]).to be_kind_of(Integer)
        async_done
      end
    end
  end

  it "can provide connection and queue monitoring" do
    api_test do
      api_request("/health?consumers=0&messages=1000") do |http, body|
        expect(http.response_header.status).to eq(204)
        expect(body).to be_empty
        api_request("/health?consumers=1000") do |http, body|
          expect(http.response_header.status).to eq(503)
          expect(body).to be_empty
          api_request("/health?consumers=1000&messages=1000") do |http, body|
            expect(http.response_header.status).to eq(503)
            async_done
          end
        end
      end
    end
  end

  it "can provide current events" do
    api_test do
      api_request("/events") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        test_event = Proc.new do |event|
          event[:check][:name] == "test"
        end
        expect(body).to contain(test_event)
        async_done
      end
    end
  end

  it "can provide current events for a specific client" do
    api_test do
      api_request("/events/i-424242") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        test_event = Proc.new do |event|
          event[:check][:name] == "test"
        end
        expect(body).to contain(test_event)
        async_done
      end
    end
  end

  it "can create a client" do
    api_test do
      options = {
        :body => {
          :name => "i-888888",
          :address => "8.8.8.8",
          :subscriptions => [
            "test"
          ]
        }
      }
      api_request("/clients", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        expect(body).to be_kind_of(Hash)
        expect(body[:name]).to eq("i-888888")
        async_done
      end
    end
  end

  it "can not create a client with an invalid post body (invalid name)" do
    api_test do
      options = {
        :body => {
          :name => "i-$$$$$$",
          :address => "8.8.8.8",
          :subscriptions => [
            "test"
          ]
        }
      }
      api_request("/clients", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can not create a client with an invalid post body (multiline name)" do
    api_test do
      options = {
        :body => {
          :name => "i-424242\ni-424242",
          :address => "8.8.8.8",
          :subscriptions => [
            "test"
          ]
        }
      }
      api_request("/clients", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can not create a client with an invalid post body (missing address)" do
    api_test do
      options = {
        :body => {
          :name => "i-424242",
          :subscriptions => [
            "test"
          ]
        }
      }
      api_request("/clients", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can not create a client with an invalid post body (invalid subscriptions)" do
    api_test do
      options = {
        :body => {
          :name => "i-424242",
          :address => "8.8.8.8",
          :subscriptions => "invalid"
        }
      }
      api_request("/clients", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can provide current clients" do
    api_test do
      api_request("/clients") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        test_client = Proc.new do |client|
          client[:name] == "i-424242"
        end
        expect(body).to contain(test_client)
        async_done
      end
    end
  end

  it "can provide defined checks" do
    api_test do
      api_request("/checks") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        test_check = Proc.new do |check|
          check[:name] == "tokens"
        end
        expect(body).to contain(test_check)
        async_done
      end
    end
  end

  it "can provide a specific event" do
    api_test do
      api_request("/event/i-424242/test") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Hash)
        expect(body[:client]).to be_kind_of(Hash)
        expect(body[:check]).to be_kind_of(Hash)
        expect(body[:client][:name]).to eq("i-424242")
        expect(body[:check][:name]).to eq("test")
        expect(body[:check][:output]).to eq("WARNING")
        expect(body[:check][:status]).to eq(1)
        expect(body[:check][:issued]).to be_within(10).of(epoch)
        expect(body[:action]).to eq("create")
        expect(body[:occurrences]).to eq(1)
        async_done
      end
    end
  end

  it "can not provide a nonexistent event" do
    api_test do
      api_request("/event/i-424242/nonexistent") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can delete an event" do
    api_test do
      result_queue do |payload|
        result = MultiJson.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:name]).to eq("test")
        expect(result[:check][:status]).to eq(0)
        timer(0.5) do
          async_done
        end
      end
      timer(0.5) do
        api_request("/event/i-424242/test", :delete) do |http, body|
          expect(http.response_header.status).to eq(202)
          expect(body).to include(:issued)
        end
      end
    end
  end

  it "can not delete a nonexistent event" do
    api_test do
      api_request("/event/i-424242/nonexistent", :delete) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can resolve an event" do
    api_test do
      result_queue do |payload|
        result = MultiJson.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:name]).to eq("test")
        expect(result[:check][:status]).to eq(0)
        timer(0.5) do
          async_done
        end
      end
      timer(0.5) do
        options = {
          :body => {
            :client => "i-424242",
            :check => "test"
          }
        }
        api_request("/resolve", :post, options) do |http, body|
          expect(http.response_header.status).to eq(202)
          expect(body).to include(:issued)
        end
      end
    end
  end

  it "can not resolve a nonexistent event" do
    api_test do
      options = {
        :body => {
          :client => "i-424242",
          :check => "nonexistent"
        }
      }
      api_request("/resolve", :post, options) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can not resolve an event with an invalid post body" do
    api_test do
      options = {
        :body => "i-424242/test"
      }
      api_request("/resolve", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can not resolve an event when missing data" do
    api_test do
      options = {
        :body => {
          :client => "i-424242"
        }
      }
      api_request("/resolve", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide a specific client" do
    api_test do
      api_request("/client/i-424242") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Hash)
        expect(body[:name]).to eq("i-424242")
        expect(body[:address]).to eq("127.0.0.1")
        expect(body[:subscriptions]).to eq(["test"])
        expect(body[:timestamp]).to be_within(10).of(epoch)
        async_done
      end
    end
  end

  it "can create and provide a client" do
    api_test do
      options = {
        :body => {
          :name => "i-888888",
          :address => "8.8.8.8",
          :subscriptions => [
            "test"
          ]
        }
      }
      api_request("/clients", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        expect(body).to be_kind_of(Hash)
        expect(body[:name]).to eq("i-888888")
        api_request("/client/i-888888") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body).to be_kind_of(Hash)
          expect(body[:name]).to eq("i-888888")
          expect(body[:address]).to eq("8.8.8.8")
          expect(body[:subscriptions]).to eq(["test"])
          expect(body[:keepalives]).to be(false)
          expect(body[:timestamp]).to be_within(10).of(epoch)
          async_done
        end
      end
    end
  end

  it "can not provide a nonexistent client" do
    api_test do
      api_request("/client/nonexistent") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can request check history for a client" do
    api_test do
      api_request("/clients/i-424242/history") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        expect(body.size).to eq(1)
        expect(body[0][:check]).to eq("test")
        expect(body[0][:history]).to be_kind_of(Array)
        expect(body[0][:last_execution]).to eq(1363224805)
        expect(body[0][:last_status]).to eq(0)
        expect(body[0][:last_result]).to be_kind_of(Hash)
        expect(body[0][:last_result][:output]).to eq("WARNING")
        async_done
      end
    end
  end

  it "can delete a client" do
    api_test do
      api_request("/client/i-424242", :delete) do |http, body|
        expect(http.response_header.status).to eq(202)
        expect(body).to include(:issued)
        async_done
      end
    end
  end

  it "can not delete a noexistent client" do
    api_test do
      api_request("/client/nonexistent", :delete) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide a specific defined check" do
    api_test do
      api_request("/check/tokens") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Hash)
        expect(body[:name]).to eq("tokens")
        expect(body[:interval]).to eq(1)
        async_done
      end
    end
  end

  it "can not provide a nonexistent defined check" do
    api_test do
      api_request("/check/nonexistent") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can issue a check request" do
    api_test do
      options = {
        :body => {
          :check => "tokens",
          :subscribers => [
            "test",
            1
          ]
        }
      }
      api_request("/request", :post, options) do |http, body|
        expect(http.response_header.status).to eq(202)
        expect(body).to include(:issued)
        async_done
      end
    end
  end

  it "can not issue a check request with an invalid post body" do
    api_test do
      options = {
        :body => {
          :check => "tokens",
          :subscribers => "invalid"
        }
      }
      api_request("/request", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can not issue a check request when missing data" do
    api_test do
      options = {
        :body => {
          :subscribers => [
            "test"
          ]
        }
      }
      api_request("/request", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can not issue a check request for a nonexistent defined check" do
    api_test do
      options = {
        :body => {
          :check => "nonexistent",
          :subscribers => [
            "test"
          ]
        }
      }
      api_request("/request", :post, options) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can create a stash (json document)" do
    api_test do
      options = {
        :body => {
          :path => "tester",
          :content => {
            :key => "value"
          }
        }
      }
      api_request("/stashes", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        expect(body).to include(:path)
        expect(body[:path]).to eq("tester")
        redis.get("stash:tester") do |stash_json|
          stash = MultiJson.load(stash_json)
          expect(stash).to eq({:key => "value"})
          redis.ttl("stash:tester") do |ttl|
            expect(ttl).to eq(-1)
            async_done
          end
        end
      end
    end
  end

  it "can not create a stash when missing data" do
    api_test do
      options = {
        :body => {
          :path => "tester"
        }
      }
      api_request("/stashes", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        expect(body).to be_empty
        redis.exists("stash:tester") do |exists|
          expect(exists).to be(false)
          async_done
        end
      end
    end
  end

  it "can not create a non-json stash" do
    api_test do
      options = {
        :body => {
          :path => "tester",
          :content => "value"
        }
      }
      api_request("/stashes", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        expect(body).to be_empty
        redis.exists("stash:tester") do |exists|
          expect(exists).to be(false)
          async_done
        end
      end
    end
  end

  it "can create a stash with id (path)" do
    api_test do
      options = {
        :body => {
          :key => "value"
        }
      }
      api_request("/stash/tester", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        expect(body).to include(:path)
        redis.get("stash:tester") do |stash_json|
          stash = MultiJson.load(stash_json)
          expect(stash).to eq({:key => "value"})
          async_done
        end
      end
    end
  end

  it "can not create a non-json stash with id" do
    api_test do
      options = {
        :body => "should fail"
      }
      api_request("/stash/tester", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        expect(body).to be_empty
        redis.exists("stash:tester") do |exists|
          expect(exists).to be(false)
          async_done
        end
      end
    end
  end

  it "can provide a stash" do
    api_test do
      api_request("/stash/test/test") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Hash)
        expect(body[:key]).to eq("value")
        async_done
      end
    end
  end

  it "can not provide a nonexistent stash" do
    api_test do
      api_request("/stash/nonexistent") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide multiple stashes" do
    api_test do
      api_request("/stashes") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        expect(body[0]).to be_kind_of(Hash)
        expect(body[0][:path]).to eq("test/test")
        expect(body[0][:content]).to eq({:key => "value"})
        expect(body[0][:expire]).to be_within(3).of(3600)
        async_done
      end
    end
  end

  it "can delete a stash" do
    api_test do
      api_request("/stash/test/test", :delete) do |http, body|
        expect(http.response_header.status).to eq(204)
        expect(body).to be_empty
        redis.exists("stash:test/test") do |exists|
          expect(exists).to be(false)
          async_done
        end
      end
    end
  end

  it "can not delete a nonexistent stash" do
    api_test do
      api_request("/stash/nonexistent", :delete) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide a list of aggregates" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis
      server.aggregate_check_result(client_template, check_template)
      timer(1) do
        api_request("/aggregates") do |http, body|
          expect(body).to be_kind_of(Array)
          test_aggregate = Proc.new do |aggregate|
            aggregate[:check] == "test"
          end
          expect(body).to contain(test_aggregate)
          async_done
        end
      end
    end
  end

  it "can provide an aggregate list" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis
      timestamp = epoch
      3.times do |index|
        check = check_template
        check[:issued] = timestamp + index
        server.aggregate_check_result(client_template, check)
      end
      timer(1) do
        api_request("/aggregates/test") do |http, body|
          expect(body).to be_kind_of(Array)
          expect(body.size).to eq(3)
          expect(body).to include(timestamp)
          api_request("/aggregates/test?limit=1") do |http, body|
            expect(body.size).to eq(1)
            api_request("/aggregates/test?limit=1&age=30") do |http, body|
              expect(body).to be_empty
              async_done
            end
          end
        end
      end
    end
  end

  it "can delete aggregates" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis
      server.aggregate_check_result(client_template, check_template)
      timer(1) do
        api_request("/aggregates/test", :delete) do |http, body|
          expect(http.response_header.status).to eq(204)
          expect(body).to be_empty
          redis.sismember("aggregates", "test") do |exists|
            expect(exists).to be(false)
            async_done
          end
        end
      end
    end
  end

  it "can not delete nonexistent aggregates" do
    api_test do
      api_request("/aggregates/nonexistent", :delete) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide a specific aggregate with parameters" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis
      check = check_template
      timestamp = epoch
      check[:issued] = timestamp
      server.aggregate_check_result(client_template, check)
      timer(1) do
        parameters = "?results=true&summarize=output"
        api_request("/aggregates/test/#{timestamp}#{parameters}") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body).to be_kind_of(Hash)
          expect(body[:ok]).to eq(0)
          expect(body[:warning]).to eq(1)
          expect(body[:critical]).to eq(0)
          expect(body[:unknown]).to eq(0)
          expect(body[:total]).to eq(1)
          expect(body[:results]).to be_kind_of(Array)
          expect(body[:results].size).to eq(1)
          expect(body[:results][0][:client]).to eq("i-424242")
          expect(body[:results][0][:output]).to eq("WARNING")
          expect(body[:results][0][:status]).to eq(1)
          expect(body[:outputs]).to be_kind_of(Hash)
          expect(body[:outputs].size).to eq(1)
          expect(body[:outputs][:"WARNING"]).to eq(1)
          async_done
        end
      end
    end
  end

  it "can not provide a nonexistent aggregate" do
    api_test do
      api_request("/aggregates/test/#{epoch}") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can accept options requests without authentication" do
    api_test do
      options = {
        :head => {
          :authorization => nil
        }
      }
      api_request("/events", :options, options) do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide cors headers" do
    api_test do
      api_request("/events") do |http, body|
        cors_headers = {
          :origin => http.response_header["ACCESS_CONTROL_ALLOW_ORIGIN"],
          :methods => http.response_header["ACCESS_CONTROL_ALLOW_METHODS"],
          :credentials => http.response_header["ACCESS_CONTROL_ALLOW_CREDENTIALS"],
          :headers => http.response_header["ACCESS_CONTROL_ALLOW_HEADERS"]
        }
        expected_headers = "Origin, X-Requested-With, Content-Type, Accept, Authorization"
        expect(cors_headers[:origin]).to eq("*")
        expect(cors_headers[:methods]).to eq("GET, POST, PUT, DELETE, OPTIONS")
        expect(cors_headers[:credentials]).to eq("true")
        expect(cors_headers[:headers]).to eq(expected_headers)
        async_done
      end
    end
  end

  it "does not receive a response body when not authorized" do
    api_test do
      options = {
        :head => {
          :authorization => nil
        }
      }
      api_request("/events", :put, options) do |http, body|
        expect(http.response_header.status).to eq(401)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "does not create a stash when not authorized" do
    api_test do
      options = {
        :head => {
          :authorization => nil
        },
        :body => {
          :path => "not_authorized",
          :content => {
            :key => "value"
          }
        }
      }
      api_request("/stashes", :post, options) do |http, body|
        expect(http.response_header.status).to eq(401)
        expect(body).to be_empty
        redis.exists("stash:not_authorized") do |exists|
          expect(exists).to eq(false)
          async_done
        end
      end
    end
  end

  it "can provide current results" do
    api_test do
      api_request("/results") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        test_result = Proc.new do |result|
          result_template(@check)
        end
        expect(body).to contain(test_result)
        async_done
      end
    end
  end

  it "can provide current results for a specific client" do
    api_test do
      api_request("/results/i-424242") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        test_result = Proc.new do |result|
          result_template(@check)
        end
        expect(body).to contain(test_result)
        async_done
      end
    end
  end

  it "can provide a specific result" do
    api_test do
      api_request("/results/i-424242/test") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Hash)
        expect(body).to eq(result_template(@check))
        async_done
      end
    end
  end
end
