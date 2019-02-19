require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/api/process"
require "sensu/server/process"

describe "Sensu::API::Process" do
  include Helpers

  before do
    async_wrapper do
      client = client_template
      client[:timestamp] = epoch
      client[:redact] = ["supersecret"]
      client[:supersecret] = "this should get redacted"
      @event = event_template
      @check = check_template
      redis.flushdb do
        redis.set("client:i-424242", Sensu::JSON.dump(client)) do
          redis.sadd("clients", "i-424242") do
            redis.hset("events:i-424242", "test", Sensu::JSON.dump(@event)) do
              redis.set("result:i-424242:test", Sensu::JSON.dump(@check)) do
                redis.set("stash:test/test", Sensu::JSON.dump({:key => "value"})) do
                  redis.expire("stash:test/test", 3600) do
                    redis.sadd("stashes", "test/test") do
                      redis.sadd("result:i-424242", "test") do
                        redis.rpush("history:i-424242:test", 1) do
                          redis.set("history:i-424242:test:last_ok", Time.now.to_i) do
                            client[:name] = "i-555555"
                            redis.set("client:i-555555", Sensu::JSON.dump(client)) do
                              redis.sadd("clients", "i-555555") do
                                redis.set("result:i-555555:test", Sensu::JSON.dump(@check)) do
                                  redis.sadd("result:i-555555", "test") do
                                    redis.rpush("history:i-555555:test", 1) do
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
            end
          end
        end
      end
    end
  end

  it "can handle integer parameters" do
    handler = Sensu::API::HTTPHandler.new(nil)
    expect(handler.integer_parameter("42")).to eq(42)
    expect(handler.integer_parameter("abc")).to eq(nil)
    expect(handler.integer_parameter("42\nabc")).to eq(nil)
  end

  it "can provide the running configuration settings with redaction" do
    api_test do
      http_request(4567, "/settings") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body[:client][:name]).to eq("i-424242")
        expect(body[:client][:service][:password]).to eq("REDACTED")
        http_request(4567, "/settings?redacted=false") do |http, body|
          expect(body[:client][:service][:password]).to eq("secret")
          async_done
        end
      end
    end
  end

  it "can respond with a 404 when a route could not be found" do
    api_test do
      http_request(4567, "/missing") do |http, body|
        expect(http.response_header.status).to eq(404)
        async_done
      end
    end
  end

  it "can respond with a 405 when a http method is not supported by a route" do
    api_test do
      http_request(4567, "/info", :put) do |http, body|
        expect(http.response_header.status).to eq(405)
        expect(http.response_header["Allow"]).to eq("GET, HEAD")
        async_done
      end
    end
  end

  it "can provide basic version and health information" do
    @server = Sensu::Server::Process.new(options)
    async_wrapper do
      @server.setup_connections do
        @server.update_server_registry do
          api_test do
            http_request(4567, "/info") do |http, body|
              expect(http.response_header.status).to eq(200)
              expect(body[:sensu][:version]).to eq(Sensu::VERSION)
              expect(body[:sensu][:settings][:hexdigest]).to be_kind_of(String)
              expect(body[:redis][:connected]).to be(true)
              expect(body[:transport][:name]).to eq("rabbitmq")
              expect(body[:transport][:connected]).to be(true)
              expect(body[:transport][:keepalives][:messages]).to be_kind_of(Integer)
              expect(body[:transport][:keepalives][:consumers]).to be_kind_of(Integer)
              expect(body[:transport][:results][:messages]).to be_kind_of(Integer)
              expect(body[:transport][:results][:consumers]).to be_kind_of(Integer)
              expect(body[:servers]).to be_kind_of(Array)
              expect(body[:servers].length).to eq(1)
              async_done
            end
          end
        end
      end
    end
  end

  it "can provide connection and queue monitoring" do
    api_test do
      http_request(4567, "/health?consumers=0&messages=1000") do |http, body|
        expect(http.response_header.status).to eq(204)
        expect(http.response_header.http_reason).to eq('No Content')
        expect(body).to be_empty
        http_request(4567, "/health?consumers=1000") do |http, body|
          expect(http.response_header.status).to eq(412)
          expect(body).to eq(["keepalive consumers (0) less than min_consumers (1000)", "result consumers (0) less than min_consumers (1000)"])
          http_request(4567, "/health?consumers=1000&messages=1000") do |http, body|
            expect(http.response_header.status).to eq(412)
            async_done
          end
        end
      end
    end
  end

  it "can provide current events" do
    api_test do
      http_request(4567, "/events") do |http, body|
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

  it "can provide current events with pagination" do
    api_test do
      http_request(4567, "/events?limit=1") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        expect(body.length).to eq(1)
        http_request(4567, "/events?limit=1&offset=1") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body).to be_kind_of(Array)
          expect(body).to be_empty
          async_done
        end
      end
    end
  end

  it "can provide current events for a specific client" do
    api_test do
      http_request(4567, "/events/i-424242") do |http, body|
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

  it "can provide current events for a specific client with pagination" do
    api_test do
      http_request(4567, "/events/i-424242?limit=1") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        expect(body.length).to eq(1)
        http_request(4567, "/events/i-424242?limit=1&offset=1") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body).to be_kind_of(Array)
          expect(body).to be_empty
          async_done
        end
      end
    end
  end

  it "can provide current incidents" do
    api_test do
      http_request(4567, "/incidents") do |http, body|
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

  it "can provide current incidents for a specific client" do
    api_test do
      http_request(4567, "/incidents/i-424242") do |http, body|
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
      http_request(4567, "/clients", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        expect(body).to be_kind_of(Hash)
        expect(body[:name]).to eq("i-888888")
        async_done
      end
    end
  end

  it "can create a client without configured subscriptions" do
    api_test do
      options = {
        :body => {
          :name => "i-888888",
          :address => "8.8.8.8"
        }
      }
      http_request(4567, "/clients", :post, options) do |http, body|
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
      http_request(4567, "/clients", :post, options) do |http, body|
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
      http_request(4567, "/clients", :post, options) do |http, body|
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
      http_request(4567, "/clients", :post, options) do |http, body|
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
      http_request(4567, "/clients", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can provide current clients" do
    api_test do
      http_request(4567, "/clients") do |http, body|
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


  it "can provide current clients with redacted attributes" do
    api_test do
      http_request(4567, "/clients") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        test_client = Proc.new do |client|
          client[:supersecret] == "REDACTED"
        end
        expect(body).to contain(test_client)
        async_done
      end
    end
  end

  it "can provide defined checks" do
    api_test do
      http_request(4567, "/checks") do |http, body|
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

  it "can provide defined checks with pagination" do
    api_test do
      http_request(4567, "/checks?limit=1") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        expect(body.length).to eq(1)
        http_request(4567, "/checks?limit=1&offset=1") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body).to be_kind_of(Array)
          expect(body.length).to eq(1)
          async_done
        end
      end
    end
  end

  it "can provide defined checks without standalone checks" do
    api_test do
      http_request(4567, "/checks") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        test_check = Proc.new do |check|
          check[:name] == "standalone"
        end
        expect(body).to_not contain(test_check)
        async_done
      end
    end
  end

  it "can provide defined checks that match filter parameters" do
    api_test do
      http_request(4567, "/checks?filter.name=tokens&filter.interval=1") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        expect(body.size).to eq(1)
        expect(body.first[:name]).to eq("tokens")
        async_done
      end
    end
  end

  it "can provide a specific check" do
    api_test do
      http_request(4567, "/checks/merger") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Hash)
        expect(body).to eq({:command=>"echo -n merger", :interval=>60, :subscribers=>["test"], :name=>"merger"})
        async_done
      end
    end
  end

  it "cannot provide a specific standalone check" do
    api_test do
      http_request(4567, "/checks/standalone") do |http, body|
        expect(http.response_header.status).to eq(404)
        async_done
      end
    end
  end

  it "can provide a specific event" do
    api_test do
      http_request(4567, "/events/i-424242/test") do |http, body|
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
      http_request(4567, "/events/i-424242/nonexistent") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can delete an event" do
    api_test do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:name]).to eq("test")
        expect(result[:check][:status]).to eq(0)
        timer(0.5) do
          async_done
        end
      end
      timer(0.5) do
        http_request(4567, "/events/i-424242/test", :delete) do |http, body|
          expect(http.response_header.status).to eq(202)
          expect(body).to include(:issued)
          timer(1) do
            redis.hget("events:i-424242", "test") do |event_json|
              expect(event_json).to be_nil
            end
          end
        end
      end
    end
  end

  it "can delete an event when the client has a signature" do
    @server = Sensu::Server::Process.new(options)
    async_wrapper do
      @server.setup_connections do
        @server.setup_keepalives
        @server.setup_results
        keepalive = client_template
        keepalive[:timestamp] = epoch
        keepalive[:signature] = "foo"
        setup_transport do |transport|
          transport.publish(:direct, "keepalives", Sensu::JSON.dump(keepalive))
        end
        timer(3) do
          redis.get("client:i-424242:signature") do |signature|
            expect(signature).to eq("foo")
            check_result = result_template
            check_result[:signature] = "foo"
            check_result[:check][:name] = 'signature_test'
            @server.process_check_result(check_result)
            timer(1) do
              api_test do
                http_request(4567, "/events/i-424242/signature_test", :delete) do |http, body|
                  expect(http.response_header.status).to eq(202)
                  expect(body).to include(:issued)
                  timer(3) do
                    redis.hget("events:i-424242", "signature_test") do |event_json|
                      expect(event_json).to be_nil
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

  it "can not delete a nonexistent event" do
    api_test do
      http_request(4567, "/events/i-424242/nonexistent", :delete) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide a specific incident" do
    api_test do
      http_request(4567, "/incidents/i-424242/test") do |http, body|
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

  it "can not provide a nonexistent incident" do
    api_test do
      http_request(4567, "/incidents/i-424242/nonexistent") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can delete an incident" do
    api_test do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:name]).to eq("test")
        expect(result[:check][:status]).to eq(0)
        timer(0.5) do
          async_done
        end
      end
      timer(0.5) do
        http_request(4567, "/incidents/i-424242/test", :delete) do |http, body|
          expect(http.response_header.status).to eq(202)
          expect(body).to include(:issued)
          timer(1) do
            redis.hget("events:i-424242", "test") do |event_json|
              expect(event_json).to be_nil
            end
          end
        end
      end
    end
  end

  it "can not delete a nonexistent incident" do
    api_test do
      http_request(4567, "/incidents/i-424242/nonexistent", :delete) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can resolve an event" do
    api_test do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
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
        http_request(4567, "/resolve", :post, options) do |http, body|
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
      http_request(4567, "/resolve", :post, options) do |http, body|
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
      http_request(4567, "/resolve", :post, options) do |http, body|
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
      http_request(4567, "/resolve", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide a specific client" do
    api_test do
      http_request(4567, "/clients/i-424242") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Hash)
        expect(body[:name]).to eq("i-424242")
        expect(body[:address]).to eq("127.0.0.1")
        expect(body[:subscriptions]).to eq(["test"])
        expect(body[:timestamp]).to be_within(10).of(epoch)
        expect(body[:supersecret]).to eq("REDACTED")
        async_done
      end
    end
  end

  it "can not provide a nonexistent client" do
    api_test do
      http_request(4567, "/clients/nonexistent") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
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
      http_request(4567, "/clients", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        expect(body).to be_kind_of(Hash)
        expect(body[:name]).to eq("i-888888")
        http_request(4567, "/clients/i-888888") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body).to be_kind_of(Hash)
          expect(body[:name]).to eq("i-888888")
          expect(body[:address]).to eq("8.8.8.8")
          expect(body[:subscriptions]).to include("client:i-888888")
          expect(body[:subscriptions]).to include("test")
          expect(body[:keepalives]).to be(false)
          expect(body[:timestamp]).to be_within(10).of(epoch)
          async_done
        end
      end
    end
  end

  it "can create a client expected to produce keepalives (eventually)" do
    api_test do
      options = {
        :body => {
          :name => "i-888888",
          :address => "8.8.8.8",
          :subscriptions => [
            "test"
          ],
          :keepalives => true
        }
      }
      http_request(4567, "/clients", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        http_request(4567, "/clients/i-888888") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body[:keepalives]).to be(true)
          async_done
        end
      end
    end
  end

  it "can request check history for a client" do
    api_test do
      http_request(4567, "/clients/i-424242/history") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        expect(body.size).to eq(1)
        expect(body[0][:check]).to eq("test")
        expect(body[0][:history]).to be_kind_of(Array)
        expect(body[0][:last_execution]).to eq(1363224805)
        expect(body[0][:last_status]).to eq(1)
        expect(body[0][:last_result]).to be_kind_of(Hash)
        expect(body[0][:last_result][:output]).to eq("WARNING")
        async_done
      end
    end
  end

  it "can delete a client" do
    api_test do
      http_request(4567, "/clients/i-424242", :delete) do |http, body|
        expect(http.response_header.status).to eq(202)
        expect(body).to include(:issued)
        async_done
      end
    end
  end

  it "can not delete a noexistent client" do
    api_test do
      http_request(4567, "/clients/nonexistent", :delete) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can delete a client and invalidate keepalives and check results until deleted" do
    api_test do
      http_request(4567, "/clients/i-424242?invalidate=true", :delete) do |http, body|
        expect(http.response_header.status).to eq(202)
        expect(body).to include(:issued)
        async_done
      end
    end
  end

  it "can delete a client and invalidate keepalives and check results for an hour after deletion" do
    api_test do
      http_request(4567, "/clients/i-424242?invalidate=true&invalidate_expire=3600", :delete) do |http, body|
        expect(http.response_header.status).to eq(202)
        expect(body).to include(:issued)
        async_done
      end
    end
  end

  it "can provide a specific defined check" do
    api_test do
      http_request(4567, "/checks/tokens") do |http, body|
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
      http_request(4567, "/checks/nonexistent") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can delete a check" do
    api_test do
      http_request(4567, "/checks/test", :delete) do |http, body|
        expect(http.response_header.status).to eq(202)
        expect(body).to include(:issued)
        timer(0.5) do
          redis.exists("result:i-424242:test") do |result|
            redis.exists("history:i-424242:test") do |history|
              redis.exists("history:i-424242:test:last_ok") do |last_ok|
                expect(result).to eq(false)
                expect(history).to eq(false)
                expect(last_ok).to eq(false)
                async_done
              end
            end
          end
        end
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
            "roundrobin:rspec",
            1
          ]
        }
      }
      http_request(4567, "/request", :post, options) do |http, body|
        expect(http.response_header.status).to eq(202)
        expect(body).to include(:issued)
        async_done
      end
    end
  end

  it "can issue a check request with a reason and creator" do
    api_test do
      options = {
        :body => {
          :check => "tokens",
          :subscribers => [
            "test",
            "roundrobin:rspec",
            1
          ],
          :reason => "post deploy validation",
          :creator => "rspec"
        }
      }
      http_request(4567, "/request", :post, options) do |http, body|
        expect(http.response_header.status).to eq(202)
        expect(body).to include(:issued)
        async_done
      end
    end
  end

  it "can issue proxy check requests" do
    api_test do
      options = {
        :body => {
          :check => "unpublished_proxy"
        }
      }
      http_request(4567, "/request", :post, options) do |http, body|
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
      http_request(4567, "/request", :post, options) do |http, body|
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
      http_request(4567, "/request", :post, options) do |http, body|
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
      http_request(4567, "/request", :post, options) do |http, body|
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
      http_request(4567, "/stashes", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        expect(body).to include(:path)
        expect(body[:path]).to eq("tester")
        redis.get("stash:tester") do |stash_json|
          stash = Sensu::JSON.load(stash_json)
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
      http_request(4567, "/stashes", :post, options) do |http, body|
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
      http_request(4567, "/stashes", :post, options) do |http, body|
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
      http_request(4567, "/stash/tester", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        expect(body).to include(:path)
        redis.get("stash:tester") do |stash_json|
          stash = Sensu::JSON.load(stash_json)
          expect(stash).to eq({:key => "value"})
          async_done
        end
      end
    end
  end

  it "can create a stash with id (path) containing a uri encoded space" do
    api_test do
      options = {
        :body => {
          :key => "value"
        }
      }
      http_request(4567, "/stash/foo%20bar", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        expect(body).to include(:path)
        redis.get("stash:foo bar") do |stash_json|
          stash = Sensu::JSON.load(stash_json)
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
      http_request(4567, "/stash/tester", :post, options) do |http, body|
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
      http_request(4567, "/stash/test/test") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Hash)
        expect(body[:key]).to eq("value")
        async_done
      end
    end
  end

  it "can indicate if a stash exists" do
    api_test do
      http_request(4567, "/stash/test/test", :head) do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can not provide a nonexistent stash" do
    api_test do
      http_request(4567, "/stash/nonexistent") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide multiple stashes" do
    api_test do
      http_request(4567, "/stashes") do |http, body|
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
      http_request(4567, "/stash/test/test", :delete) do |http, body|
        expect(http.response_header.status).to eq(204)
        expect(http.response_header.http_reason).to eq('No Content')
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
      http_request(4567, "/stash/nonexistent", :delete) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide a list of aggregates" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis do
        server.aggregate_check_result(client_template, check_template)
        timer(1) do
          http_request(4567, "/aggregates") do |http, body|
            expect(body).to be_kind_of(Array)
            expect(body).to include({:name => "test"})
            async_done
          end
        end
      end
    end
  end

  it "can provide a list of aggregates with pagination" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis do
        server.aggregate_check_result(client_template, check_template)
        timer(1) do
          http_request(4567, "/aggregates?limit=1") do |http, body|
            expect(body).to be_kind_of(Array)
            expect(body.length).to eq(1)
            http_request(4567, "/aggregates?limit=1&offset=1") do |http, body|
              expect(body).to be_kind_of(Array)
              expect(body).to be_empty
              async_done
            end
          end
        end
      end
    end
  end

  it "can delete an aggregate" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis do
        server.aggregate_check_result(client_template, check_template)
        timer(1) do
          http_request(4567, "/aggregates/test", :delete) do |http, body|
            expect(http.response_header.status).to eq(204)
            expect(http.response_header.http_reason).to eq('No Content')
            expect(body).to be_empty
            redis.sismember("aggregates", "test") do |exists|
              expect(exists).to be(false)
              async_done
            end
          end
        end
      end
    end
  end

  it "can delete an aggregate with an all caps name" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis do
        check = check_template
        check[:name] = "TEST"
        server.aggregate_check_result(client_template, check)
        timer(1) do
          http_request(4567, "/aggregates/TEST", :delete) do |http, body|
            expect(http.response_header.status).to eq(204)
            expect(http.response_header.http_reason).to eq('No Content')
            expect(body).to be_empty
            redis.sismember("aggregates", "TEST") do |exists|
              expect(exists).to be(false)
              async_done
            end
          end
        end
      end
    end
  end

  it "can not delete a nonexistent aggregate" do
    api_test do
      http_request(4567, "/aggregates/nonexistent", :delete) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide an aggregate" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis do
        server.aggregate_check_result(client_template, check_template)
        timer(1) do
          http_request(4567, "/aggregates/test") do |http, body|
            expect(http.response_header.status).to eq(200)
            expect(body).to be_kind_of(Hash)
            expect(body[:clients]).to eq(1)
            expect(body[:checks]).to eq(1)
            expect(body[:results][:ok]).to eq(0)
            expect(body[:results][:warning]).to eq(1)
            expect(body[:results][:critical]).to eq(0)
            expect(body[:results][:unknown]).to eq(0)
            expect(body[:results][:total]).to eq(1)
            expect(body[:results][:stale]).to eq(0)
            async_done
          end
        end
      end
    end
  end

  it "can provide an aggregate with a result max age" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis do
        check = check_template
        check[:executed] = epoch - 128
        server.aggregate_check_result(client_template, check)
        timer(1) do
          http_request(4567, "/aggregates/test?max_age=120") do |http, body|
            expect(http.response_header.status).to eq(200)
            expect(body).to be_kind_of(Hash)
            expect(body[:clients]).to eq(1)
            expect(body[:checks]).to eq(1)
            expect(body[:results][:ok]).to eq(0)
            expect(body[:results][:warning]).to eq(0)
            expect(body[:results][:critical]).to eq(0)
            expect(body[:results][:unknown]).to eq(0)
            expect(body[:results][:total]).to eq(0)
            expect(body[:results][:stale]).to eq(1)
            async_done
          end
        end
      end
    end
  end

  it "can not provide a nonexistent aggregate" do
    api_test do
      http_request(4567, "/aggregates/nonexistent") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide aggregate client information" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis do
        server.aggregate_check_result(client_template, check_template)
        timer(1) do
          http_request(4567, "/aggregates/test/clients") do |http, body|
            expect(http.response_header.status).to eq(200)
            expect(body).to be_kind_of(Array)
            expect(body[0]).to be_kind_of(Hash)
            expect(body[0][:name]).to eq("i-424242")
            expect(body[0][:checks]).to eq(["test"])
            async_done
          end
        end
      end
    end
  end

  it "can not provide aggregate client information for a nonexistent aggregate" do
    api_test do
      http_request(4567, "/aggregates/nonexistent/clients") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide aggregate check information" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis do
        server.aggregate_check_result(client_template, check_template)
        timer(1) do
          http_request(4567, "/aggregates/test/checks") do |http, body|
            expect(http.response_header.status).to eq(200)
            expect(body).to be_kind_of(Array)
            expect(body[0]).to be_kind_of(Hash)
            expect(body[0][:name]).to eq("test")
            expect(body[0][:clients]).to eq(["i-424242"])
            async_done
          end
        end
      end
    end
  end

  it "can not provide aggregate check information for a nonexistent aggregate" do
    api_test do
      http_request(4567, "/aggregates/nonexistent/checks") do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide a aggregate result summary for a severity" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis do
        server.aggregate_check_result(client_template, check_template)
        timer(1) do
          http_request(4567, "/aggregates/test/results/warning") do |http, body|
            expect(http.response_header.status).to eq(200)
            expect(body).to be_kind_of(Array)
            expect(body[0]).to be_kind_of(Hash)
            expect(body[0][:check]).to eq("test")
            expect(body[0][:summary]).to be_kind_of(Array)
            expect(body[0][:summary][0]).to be_kind_of(Hash)
            expect(body[0][:summary][0][:output]).to eq("WARNING")
            expect(body[0][:summary][0][:total]).to eq(1)
            expect(body[0][:summary][0][:clients]).to eq(["i-424242"])
            async_done
          end
        end
      end
    end
  end

  it "can provide a aggregate result summary for a severity with a result max age" do
    api_test do
      server = Sensu::Server::Process.new(options)
      server.setup_redis do
        check = check_template
        check[:executed] = epoch - 128
        server.aggregate_check_result(client_template, check)
        timer(1) do
          http_request(4567, "/aggregates/test/results/warning?max_age=120") do |http, body|
            expect(http.response_header.status).to eq(200)
            expect(body).to be_kind_of(Array)
            expect(body).to be_empty
            async_done
          end
        end
      end
    end
  end

  it "can not provide a aggregate result summary for an invalid severity" do
    api_test do
      http_request(4567, "/aggregates/test/results/invalid") do |http, body|
        expect(http.response_header.status).to eq(400)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can not provide a aggregate result summary for a nonexistent aggregate" do
    api_test do
      http_request(4567, "/aggregates/nonexistent/results/warning") do |http, body|
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
      http_request(4567, "/events", :options, options) do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide cors headers" do
    api_test do
      http_request(4567, "/events") do |http, body|
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
      http_request(4567, "/events", :put, options) do |http, body|
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
      http_request(4567, "/stashes", :post, options) do |http, body|
        expect(http.response_header.status).to eq(401)
        expect(body).to be_empty
        redis.exists("stash:not_authorized") do |exists|
          expect(exists).to eq(false)
          async_done
        end
      end
    end
  end

  it "can publish a check result" do
    api_test do
      options = {
        :body => {
          :name => "rspec",
          :output => "WARNING",
          :status => 1
        }
      }
      http_request(4567, "/results", :post, options) do |http, body|
        expect(http.response_header.status).to eq(202)
        expect(body).to include(:issued)
        async_done
      end
    end
  end

  it "can not publish a check result with an invalid post body" do
    api_test do
      options = {
        :body => {
          :name => "rspec",
          :output => "WARNING",
          :status => 1,
          :source => "$invalid$"
        }
      }
      http_request(4567, "/results", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can not publish a check result when missing data" do
    api_test do
      options = {
        :body => {
          :name => "missing_output"
        }
      }
      http_request(4567, "/results", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can provide current results" do
    api_test do
      http_request(4567, "/results") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        test_result_one = Proc.new do |result|
          expected_check = @check.merge(:history => [1])
          expected_result = result_template(expected_check)
          expected_result[:client] = "i-424242"
          result == expected_result
        end
        test_result_two = Proc.new do |result|
          expected_check = @check.merge(:history => [1])
          expected_result = result_template(expected_check)
          expected_result[:client] = "i-555555"
          result == expected_result
        end
        expect(body).to contain(test_result_one)
        expect(body).to contain(test_result_two)
        async_done
      end
    end
  end

  it "can provide current results with pagination" do
    api_test do
      http_request(4567, "/results?limit=1") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        expect(body.length).to eq(1)
        http_request(4567, "/results?limit=1&offset=1") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body).to be_kind_of(Array)
          expect(body.length).to eq(1)
          http_request(4567, "/results?limit=1&offset=2") do |http, body|
            expect(http.response_header.status).to eq(200)
            expect(body).to be_kind_of(Array)
            expect(body).to be_empty
            async_done
          end
        end
      end
    end
  end

  it "can provide current results for a specific client" do
    api_test do
      http_request(4567, "/results/i-424242") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        test_result = Proc.new do |result|
          expected_check = @check.merge(:history => [1])
          result_template(expected_check)
        end
        expect(body).to contain(test_result)
        async_done
      end
    end
  end

  it "can provide current results for a specific client with pagination" do
    api_test do
      http_request(4567, "/results/i-424242?limit=1") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Array)
        expect(body.length).to eq(1)
        http_request(4567, "/results/i-424242?limit=1&offset=1") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body).to be_kind_of(Array)
          expect(body).to be_empty
          async_done
        end
      end
    end
  end

  it "can provide a specific result" do
    api_test do
      http_request(4567, "/results/i-424242/test") do |http, body|
        expect(http.response_header.status).to eq(200)
        expect(body).to be_kind_of(Hash)
        expected_check = @check.merge(:history => [1])
        expect(body).to eq(result_template(expected_check))
        async_done
      end
    end
  end

  it "can delete a result" do
    api_test do
      http_request(4567, "/results/i-424242/test", :delete) do |http, body|
        expect(http.response_header.status).to eq(204)
        expect(http.response_header.http_reason).to eq('No Content')
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can not delete a nonexistent result" do
    api_test do
      http_request(4567, "/results/i-424242/nonexistent", :delete) do |http, body|
        expect(http.response_header.status).to eq(404)
        expect(body).to be_empty
        async_done
      end
    end
  end

  it "can create a silenced registry entry for a subscription" do
    api_test do
      options = {
        :body => {
          :subscription => "test"
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        redis.get("silence:test:*") do |silenced_info_json|
          silenced_info = Sensu::JSON.load(silenced_info_json)
          expect(silenced_info[:id]).to eq("test:*")
          expect(silenced_info[:subscription]).to eq("test")
          expect(silenced_info[:check]).to be_nil
          expect(silenced_info[:begin]).to be_nil
          expect(silenced_info[:reason]).to be_nil
          expect(silenced_info[:creator]).to be_nil
          expect(silenced_info[:expire_on_resolve]).to eq(false)
          expect(silenced_info[:timestamp]).to be_within(10).of(Time.now.to_i)
          async_done
        end
      end
    end
  end

  it "can create a silenced registry entry for a check" do
    api_test do
      options = {
        :body => {
          :check => "test"
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        redis.get("silence:*:test") do |silenced_info_json|
          silenced_info = Sensu::JSON.load(silenced_info_json)
          expect(silenced_info[:id]).to eq("*:test")
          expect(silenced_info[:subscription]).to be_nil
          expect(silenced_info[:check]).to eq("test")
          expect(silenced_info[:begin]).to be_nil
          expect(silenced_info[:reason]).to be_nil
          expect(silenced_info[:creator]).to be_nil
          expect(silenced_info[:expire_on_resolve]).to eq(false)
          expect(silenced_info[:timestamp]).to be_within(10).of(Time.now.to_i)
          async_done
        end
      end
    end
  end

  it "can create a silenced registry entry that expires" do
    api_test do
      options = {
        :body => {
          :subscription => "test",
          :check => "test",
          :expire => 3600,
          :reason => "testing",
          :creator => "rspec",
          :expire_on_resolve => true
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        redis.get("silence:test:test") do |silenced_info_json|
          silenced_info = Sensu::JSON.load(silenced_info_json)
          expect(silenced_info[:id]).to eq("test:test")
          expect(silenced_info[:subscription]).to eq("test")
          expect(silenced_info[:check]).to eq("test")
          expect(silenced_info[:begin]).to be_nil
          expect(silenced_info[:reason]).to eq("testing")
          expect(silenced_info[:creator]).to eq("rspec")
          expect(silenced_info[:expire_on_resolve]).to eq(true)
          expect(silenced_info[:timestamp]).to be_within(10).of(Time.now.to_i)
          redis.ttl("silence:test:test") do |ttl|
            expect(ttl).to be_within(10).of(3600)
            async_done
          end
        end
      end
    end
  end

  it "can create a silenced registry entry with a begin time that expires" do
    api_test do
      begin_timestamp = Time.now.to_i + 60
      options = {
        :body => {
          :subscription => "test",
          :check => "test",
          :begin => begin_timestamp,
          :expire => 3600,
          :reason => "testing",
          :creator => "rspec",
          :expire_on_resolve => true
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        redis.get("silence:test:test") do |silenced_info_json|
          silenced_info = Sensu::JSON.load(silenced_info_json)
          expect(silenced_info[:id]).to eq("test:test")
          expect(silenced_info[:subscription]).to eq("test")
          expect(silenced_info[:check]).to eq("test")
          expect(silenced_info[:begin]).to eq(begin_timestamp)
          expect(silenced_info[:reason]).to eq("testing")
          expect(silenced_info[:creator]).to eq("rspec")
          expect(silenced_info[:expire_on_resolve]).to eq(true)
          expect(silenced_info[:timestamp]).to be_within(10).of(Time.now.to_i)
          redis.ttl("silence:test:test") do |ttl|
            expect(ttl).to be_within(10).of(3660)
            async_done
          end
        end
      end
    end
  end

  [
    "client:my-test-client",
    "roundrobin:load_balancer",
    "roundrobin:foo_bar-baz",
    "load-balancer",
    "load_balancer",
    "loadbalancer"
  ].each do |subscription|
    it "can create and retrieve silenced registry entry with a subscription e.g. #{subscription}" do
      api_test do
        options = {
          :body => {
            :subscription => subscription,
            :check => "test"
          }
        }
        http_request(4567, "/silenced", :post, options) do |http, body|
          expect(http.response_header.status).to eq(201)
          redis.get("silence:#{subscription}:test") do |silenced_info_json|
            timer(1) do
              http_request(4567, "/silenced/subscriptions/#{subscription}") do |http, body|
                expect(http.response_header.status).to eq(200)
                expect(body).to be_kind_of(Array)
                silence = body.last
                expect(silence[:id]).to eq("#{subscription}:test")
                async_done
              end
            end
          end
        end
      end
    end
  end

  it "can not create a silenced registry entry when missing a subscription and/or check" do
    api_test do
      options = {
        :body => {
          :expire => 3600,
          :reason => "testing",
          :creator => "rspec",
          :expire_on_resolve => true
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can not create a silenced registry entry with an invalid subscription" do
    api_test do
      options = {
        :body => {
          :subscription => 1,
          :check => "test"
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can not create a silenced registry entry with an invalid check" do
    api_test do
      options = {
        :body => {
          :subscription => "test",
          :check => 1
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can not create a silenced registry entry with an invalid expire" do
    api_test do
      options = {
        :body => {
          :subscription => "test",
          :check => "test",
          :expire => "3600"
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can not create a silenced registry entry with an invalid reason" do
    api_test do
      options = {
        :body => {
          :subscription => "test",
          :check => "test",
          :reason => 1
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can not create a silenced registry entry with an invalid creator" do
    api_test do
      options = {
        :body => {
          :subscription => "test",
          :check => "test",
          :creator => 1
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can not create a silenced registry entry with an invalid expire_on_resolve" do
    api_test do
      options = {
        :body => {
          :subscription => "test",
          :check => "test",
          :expire_on_resolve => "true"
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can not create a silenced registry entry with an invalid begin time" do
    api_test do
      options = {
        :body => {
          :subscription => "test",
          :check => "test",
          :begin => Time.now.to_i.to_s
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(400)
        async_done
      end
    end
  end

  it "can provide the silenced registry" do
    api_test do
      options = {
        :body => {
          :subscription => "test",
          :check => "test",
          :expire => 3600
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        http_request(4567, "/silenced") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body).to be_kind_of(Array)
          expect(body.length).to eq(1)
          silenced_info = body.first
          expect(silenced_info).to be_kind_of(Hash)
          expect(silenced_info[:id]).to eq("test:test")
          expect(silenced_info[:subscription]).to eq("test")
          expect(silenced_info[:check]).to eq("test")
          expect(silenced_info[:begin]).to be_nil
          expect(silenced_info[:expire]).to be_within(10).of(3600)
          expect(silenced_info[:timestamp]).to be_within(10).of(Time.now.to_i)
          http_request(4567, "/silenced/subscriptions/test") do |http, body|
            expect(http.response_header.status).to eq(200)
            expect(body).to be_kind_of(Array)
            expect(body.length).to eq(1)
            silenced_info = body.first
            expect(silenced_info).to be_kind_of(Hash)
            expect(silenced_info[:subscription]).to eq("test")
            expect(silenced_info[:expire]).to be_within(10).of(3600)
            http_request(4567, "/silenced/subscriptions/nonexistent") do |http, body|
              expect(http.response_header.status).to eq(200)
              expect(body).to be_kind_of(Array)
              expect(body).to be_empty
              http_request(4567, "/silenced/checks/test") do |http, body|
                expect(http.response_header.status).to eq(200)
                expect(body).to be_kind_of(Array)
                expect(body.length).to eq(1)
                silenced_info = body.first
                expect(silenced_info).to be_kind_of(Hash)
                expect(silenced_info[:check]).to eq("test")
                expect(silenced_info[:expire]).to be_within(10).of(3600)
                http_request(4567, "/silenced/checks/nonexistent") do |http, body|
                  expect(http.response_header.status).to eq(200)
                  expect(body).to be_kind_of(Array)
                  expect(body).to be_empty
                  async_done
                end
              end
            end
          end
        end
      end
    end
  end

  context "when retrieving a silenced registry entry by it's id" do
    it "can retrieve entry for silencing a specific check on all clients" do
      api_test do
        options = { :body => { :check => "test" } }
        http_request(4567, "/silenced", :post, options) do |http, body|
          http_request(4567, "/silenced/ids/*:test") do |http, body|
            expect(http.response_header.status).to eq(200)
            expect(body).to be_kind_of(Hash)
            expect(body[:id]).to eq("*:test")
            async_done
          end
        end
      end
    end

    it "can retrieve entry for silencing all checks on a specific subscription" do
      api_test do
        options = { :body => { :subscription => "test" } }
        http_request(4567, "/silenced", :post, options) do |http, body|
          http_request(4567, "/silenced/ids/test:*") do |http, body|
            expect(http.response_header.status).to eq(200)
            expect(body).to be_kind_of(Hash)
            expect(body[:id]).to eq("test:*")
            async_done
          end
        end
      end
    end

    it "cannot create an entry for silencing all checks on all subscriptions" do
      api_test do
        options = { :body => { :subscription => '*' } }
        http_request(4567, "/silenced", :post, options) do |http, body|
          expect(http.response_header.status).to eq(400)
          async_done
        end
      end
    end

    it "handles requests for nonexistant ids" do
      api_test do
        http_request(4567, "/silenced/ids/nonexistant:nonexistant") do |http, body|
          expect(http.response_header.status).to eq(404)
          expect(body).to be_empty
          async_done
        end
      end
    end

    it "handles requests for invalid ids" do
      api_test do
        http_request(4567, "/silenced/ids/invalid") do |http, body|
          expect(http.response_header.status).to eq(404)
          expect(body).to be_empty
          http_request(4567, "/silenced/ids/:invalid") do |http, body|
            expect(http.response_header.status).to eq(404)
            expect(body).to be_empty
            http_request(4567, "/silenced/ids/inv@(!alid") do |http, body|
              expect(http.response_header.status).to eq(404)
              expect(body).to be_empty
              async_done
            end
          end
        end
      end
    end
  end

  it "can clear a silenced registry entry with a subscription and check" do
    api_test do
      options = {
        :body => {
          :subscription => "test",
          :check => "test"
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        http_request(4567, "/silenced") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body).to be_kind_of(Array)
          expect(body.length).to eq(1)
          silenced_info = body.first
          expect(silenced_info).to be_kind_of(Hash)
          expect(silenced_info[:subscription]).to eq("test")
          expect(silenced_info[:check]).to eq("test")
          http_request(4567, "/silenced/clear", :post, options) do |http, body|
            expect(http.response_header.status).to eq(204)
            http_request(4567, "/silenced/clear", :post, options) do |http, body|
              expect(http.response_header.status).to eq(404)
              http_request(4567, "/silenced") do |http, body|
                expect(http.response_header.status).to eq(200)
                expect(body).to be_kind_of(Array)
                expect(body).to be_empty
                async_done
              end
            end
          end
        end
      end
    end
  end

  it "can clear a silenced registry entry with an id" do
    api_test do
      options = {
        :body => {
          :check => "test"
        }
      }
      http_request(4567, "/silenced", :post, options) do |http, body|
        expect(http.response_header.status).to eq(201)
        http_request(4567, "/silenced") do |http, body|
          expect(http.response_header.status).to eq(200)
          expect(body).to be_kind_of(Array)
          expect(body.length).to eq(1)
          silenced_info = body.first
          expect(silenced_info).to be_kind_of(Hash)
          expect(silenced_info[:id]).to eq("*:test")
          expect(silenced_info[:subscription]).to be_nil
          expect(silenced_info[:check]).to eq("test")
          options = {
            :body => {
              :id => "*:test"
            }
          }
          http_request(4567, "/silenced/clear", :post, options) do |http, body|
            expect(http.response_header.status).to eq(204)
            http_request(4567, "/silenced/clear", :post, options) do |http, body|
              expect(http.response_header.status).to eq(404)
              http_request(4567, "/silenced") do |http, body|
                expect(http.response_header.status).to eq(200)
                expect(body).to be_kind_of(Array)
                expect(body).to be_empty
                async_done
              end
            end
          end
        end
      end
    end
  end
end
