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
      @server.setup_redis do |connection|
        connection.callback do
          expect(connection.connected?).to eq(true)
          async_done
        end
      end
    end
  end

  it "can connect to the transport" do
    async_wrapper do
      @server.setup_transport do
        timer(0.5) do
          async_done
        end
      end
    end
  end

  it "can consume client keepalives" do
    async_wrapper do
      @server.setup_connections do
        @server.setup_keepalives
        keepalive = client_template
        keepalive[:timestamp] = epoch
        redis.flushdb do
          timer(1) do
            setup_transport do |transport|
              transport.publish(:direct, "keepalives", Sensu::JSON.dump(keepalive))
            end
            timer(1) do
              redis.sismember("clients", "i-424242") do |exists|
                expect(exists).to be(true)
                redis.get("client:i-424242") do |client_json|
                  client = Sensu::JSON.load(client_json)
                  # keepalive processing adds a per-client subscription
                  processed_keepalive = keepalive.dup
                  processed_keepalive[:subscriptions] = (
                    keepalive[:subscriptions] + ["client:#{keepalive[:name]}"]
                  ).uniq
                  expect(client).to eq(processed_keepalive)
                  read_event_file = Proc.new do
                    begin
                      event_file = IO.read("/tmp/sensu_client_registration.json")
                      Sensu::JSON.load(event_file)
                    rescue
                      retry
                    end
                  end
                  compare_event_file = Proc.new do |event_file|
                    expect(event_file[:check][:name]).to eq("registration")
                    expect(event_file[:client]).to eq(processed_keepalive)
                    async_done
                  end
                  EM.defer(read_event_file, compare_event_file)
                end
              end
            end
          end
        end
      end
    end
  end

  it "can consume client keepalives with client signatures" do
    async_wrapper do
      @server.setup_connections do
        @server.setup_keepalives
        keepalive = client_template
        keepalive[:timestamp] = epoch
        keepalive[:signature] = "foo"
        # keepalive processing adds a per-client subscription
        processed_keepalive = keepalive.dup
        processed_keepalive[:subscriptions] = (
          keepalive[:subscriptions] + ["client:#{keepalive[:name]}"]
        ).uniq
        redis.flushdb do
          timer(1) do
            setup_transport do |transport|
              transport.publish(:direct, "keepalives", Sensu::JSON.dump(keepalive))
              timer(1) do
                redis.get("client:i-424242") do |client_json|
                  client = Sensu::JSON.load(client_json)
                  expect(client).to eq(processed_keepalive)
                  redis.get("client:i-424242:signature") do |signature|
                    expect(signature).to eq("foo")
                    malicious = keepalive.dup
                    malicious[:timestamp] = epoch
                    malicious[:signature] = "bar"
                    transport.publish(:direct, "keepalives", Sensu::JSON.dump(malicious))
                    timer(1) do
                      redis.get("client:i-424242") do |client_json|
                        client = Sensu::JSON.load(client_json)
                        expect(client).to eq(processed_keepalive)
                        redis.get("client:i-424242:signature") do |signature|
                          expect(signature).to eq("foo")
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
      @server.setup_redis do
        clients = ["foo", "bar", "baz", "qux"]
        redis.flushdb do
          clients.each do |client_name|
            client = client_template
            client[:name] = client_name
            check = check_template
            check[:aggregate] = true
            @server.aggregate_check_result(client, check)
            check = check_template
            check[:aggregate] = "foobar"
            @server.aggregate_check_result(client, check)
          end
          timer(2) do
            redis.sismember("aggregates", "test") do |exists|
              expect(exists).to be(true)
              redis.sismember("aggregates", "foobar") do |exists|
                expect(exists).to be(true)
                expected_members = clients.map do |client_name|
                  "#{client_name}:test"
                end
                redis.smembers("aggregates:test") do |aggregate_members|
                  expect(aggregate_members).to match_array(expected_members)
                  redis.smembers("aggregates:foobar") do |aggregate_members|
                    expect(aggregate_members).to match_array(expected_members)
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

  it "can aggregate check results across multiple named aggregates" do
    async_wrapper do
      aggregates = ["foo", "bar"]
      redis.flushdb do
        client = client_template
        client[:name] = "aggro"
        check = check_template
        check[:aggregates] = aggregates
        @server.setup_redis do
          @server.aggregate_check_result(client, check)
          timer(2) do
            redis.sismember("aggregates", "foo") do |exists|
              expect(exists).to be(true)
              redis.smembers("aggregates:foo") do |aggregate_members|
                expect(aggregate_members).to include("aggro:test")
                redis.sismember("aggregates", "bar") do |exists|
                  expect(exists).to be(true)
                  redis.smembers("aggregates:bar") do |aggregate_members|
                    expect(aggregate_members).to include("aggro:test")
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

  it "can process results from proxy clients" do
    async_wrapper do
      @server.setup_redis do
        redis.flushdb do
          @server.setup_transport do
            result = result_template
            result[:check][:name] = "unpublished_proxy"
            result[:check][:command] = "echo 127.0.0.1 && exit 1"
            result[:check][:source] = "i-424242"
            @server.process_check_result(result)
            timer(1) do
              redis.hget("events:i-424242", "unpublished_proxy") do |event_json|
                event = Sensu::JSON.load(event_json)
                expect(event[:check][:command]).to eq("echo :::address::: && exit 1")
                async_done
              end
            end
          end
        end
      end
    end
  end

  it "can process results with flap detection" do
    FileUtils.rm_rf("/tmp/sensu_event")
    expect(File.exists?("/tmp/sensu_event")).to eq(false)
    async_wrapper do
      @server.setup_redis do
        redis.flushdb do
          client = client_template
          redis.set("client:i-424242", Sensu::JSON.dump(client)) do
            26.times do |index|
              result = result_template
              result[:check][:low_flap_threshold] = 5
              result[:check][:high_flap_threshold] = 20
              result[:check][:status] = index % 2
              result[:check][:executed] = epoch
              @server.process_check_result(result)
            end
            timer(1) do
              redis.llen("history:i-424242:test") do |length|
                expect(length).to eq(21)
                redis.hget("events:i-424242", "test") do |event_json|
                  event = Sensu::JSON.load(event_json)
                  expect(event[:action]).to eq("flapping")
                  expect(event[:occurrences]).to be_within(2).of(1)
                  expect(event[:last_ok]).to be_within(10).of(epoch)
                  26.times do |index|
                    result = result_template
                    result[:check][:low_flap_threshold] = 5
                    result[:check][:high_flap_threshold] = 20
                    result[:check][:status] = 0
                    result[:check][:handler] = "file"
                    @server.process_check_result(result)
                  end
                  timer(1) do
                    redis.hexists("events:i-424242", "test") do |exists|
                      expect(exists).to be(false)
                      expect(File.exists?("/tmp/sensu_event")).to eq(true)
                      event_file_json = IO.read("/tmp/sensu_event")
                      event = Sensu::JSON.load(event_file_json)
                      expect(event[:action]).to eq("resolve")
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

  it "can force resolve a flapping event" do
    async_wrapper do
      @server.setup_redis do
        redis.flushdb do
          client = client_template
          redis.set("client:i-424242", Sensu::JSON.dump(client)) do
            26.times do |index|
              result = result_template
              result[:check][:low_flap_threshold] = 5
              result[:check][:high_flap_threshold] = 20
              result[:check][:status] = index % 2
              result[:check][:executed] = epoch
              @server.process_check_result(result)
            end
            timer(1) do
              redis.hget("events:i-424242", "test") do |event_json|
                event = Sensu::JSON.load(event_json)
                expect(event[:action]).to eq("flapping")
                expect(event[:occurrences]).to be_within(2).of(1)
                expect(event[:last_ok]).to be_within(10).of(epoch)
                result = result_template
                result[:check][:low_flap_threshold] = 5
                result[:check][:high_flap_threshold] = 20
                result[:check][:status] = 0
                result[:check][:force_resolve] = true
                @server.process_check_result(result)
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

  it "can process results with silencing" do
    async_wrapper do
      @server.setup_redis do
        redis.flushdb do
          redis.set("client:i-424242", Sensu::JSON.dump(client_template)) do
            silenced_info = {
              :id => "test:*"
            }
            redis.set("silence:test:*", Sensu::JSON.dump(silenced_info)) do
              silenced_info[:id] = "*:test"
              redis.set("silence:*:test", Sensu::JSON.dump(silenced_info)) do
                silenced_info[:id] = "test:test"
                redis.set("silence:test:test", Sensu::JSON.dump(silenced_info)) do
                  @server.process_check_result(result_template)
                  timer(1) do
                    redis.hget("events:i-424242", "test") do |event_json|
                      event = Sensu::JSON.load(event_json)
                      expect(event[:silenced]).to eq(true)
                      expect(event[:silenced_by]).to eq(["test:*", "test:test", "*:test"])
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

  it "can expire silenced entries on event resolution" do
    FileUtils.rm_rf("/tmp/sensu_event")
    expect(File.exists?("/tmp/sensu_event")).to eq(false)
    async_wrapper do
      @server.setup_redis do
        redis.flushdb do
          redis.set("client:i-424242", Sensu::JSON.dump(client_template)) do
            silenced_info = {
              :id => "test:*",
              :expire_on_resolve => true
            }
            redis.set("silence:test:*", Sensu::JSON.dump(silenced_info)) do
              result = result_template
              result[:check][:handler] = "file"
              @server.process_check_result(result)
              timer(1) do
                expect(File.exists?("/tmp/sensu_event")).to eq(false)
                result[:check][:status] = 0
                @server.process_check_result(result)
                timer(1) do
                  expect(File.exists?("/tmp/sensu_event")).to eq(true)
                  async_done
                end
              end
            end
          end
        end
      end
    end
  end

  it "can process results with scheduled maintenance silencing" do
    async_wrapper do
      @server.setup_redis do
        redis.flushdb do
          redis.set("client:i-424242", Sensu::JSON.dump(client_template)) do
            silenced_info = {
              :id => "test:*",
              :begin => Time.now.to_i - 60
            }
            redis.set("silence:test:*", Sensu::JSON.dump(silenced_info)) do
              silenced_info[:id] = "*:test"
              silenced_info[:begin] = Time.now.to_i + 60
              redis.set("silence:*:test", Sensu::JSON.dump(silenced_info)) do
                @server.process_check_result(result_template)
                timer(1) do
                  redis.hget("events:i-424242", "test") do |event_json|
                    event = Sensu::JSON.load(event_json)
                    expect(event[:silenced]).to eq(true)
                    expect(event[:silenced_by]).to eq(["test:*"])
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

  it "can have event id and occurrence watermark persist until the event is resolved" do
    async_wrapper do
      @server.setup_redis do
        redis.flushdb do
          client = client_template
          redis.set("client:i-424242", Sensu::JSON.dump(client)) do
            @server.process_check_result(result_template)
            @server.process_check_result(result_template)
            timer(2) do
              redis.hget("events:i-424242", "test") do |event_json|
                event = Sensu::JSON.load(event_json)
                event_id = event[:id]
                expect(event[:occurrences]).to eq(2)
                expect(event[:occurrences_watermark]).to eq(2)
                result = result_template
                result[:check][:status] = 2
                @server.process_check_result(result)
                timer(2) do
                  redis.hget("events:i-424242", "test") do |event_json|
                    event = Sensu::JSON.load(event_json)
                    expect(event[:id]).to eq(event_id)
                    expect(event[:occurrences]).to eq(1)
                    expect(event[:occurrences_watermark]).to eq(2)
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

  it "can not resolve events when provided the option" do
    async_wrapper do
      @server.setup_redis do
        redis.flushdb do
          client = client_template
          redis.set("client:i-424242", Sensu::JSON.dump(client)) do
            result = result_template
            result[:check][:auto_resolve] = false
            @server.process_check_result(result)
            timer(1) do
              redis.hget("events:i-424242", "test") do |event_json|
                event = Sensu::JSON.load(event_json)
                expect(event[:action]).to eq("create")
                expect(event[:occurrences]).to eq(1)
                result[:check][:status] = 0
                @server.process_check_result(result)
                timer(1) do
                  redis.hget("events:i-424242", "test") do |event_json|
                    event = Sensu::JSON.load(event_json)
                    expect(event[:action]).to eq("create")
                    expect(event[:occurrences]).to eq(1)
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

  it "can consume results" do
    async_wrapper(30) do
      @server.setup_connections do
        @server.setup_results
        redis.flushdb do
          timer(1) do
            client = client_template
            redis.set("client:i-424242", Sensu::JSON.dump(client)) do
              result = result_template
              setup_transport do |transport|
                transport.publish(:direct, "results", Sensu::JSON.dump(result))
                timer(1) do
                  transport.publish(:direct, "results", Sensu::JSON.dump(result))
                  timer(2) do
                    redis.sismember("result:i-424242", "test") do |is_member|
                      expect(is_member).to be(true)
                      redis.get("result:i-424242:test") do |result_json|
                        result = Sensu::JSON.load(result_json)
                        expect(result[:output]).to eq("WARNING")
                        timer(7) do
                          redis.hget("events:i-424242", "test") do |event_json|
                            event = Sensu::JSON.load(event_json)
                            expect(event[:id]).to be_kind_of(String)
                            expect(event[:check][:status]).to eq(1)
                            expect(event[:occurrences]).to eq(2)
                            expect(event[:occurrences_watermark]).to eq(2)
                            expect(event[:last_ok]).to be_nil
                            expect(event[:silenced]).to eq(false)
                            expect(event[:silenced_by]).to be_empty
                            expect(event[:action]).to eq("create")
                            expect(event[:timestamp]).to be_within(10).of(epoch)
                            read_event_file = Proc.new do
                              begin
                                event_file = IO.read("/tmp/sensu_event_bridge.json")
                                Sensu::JSON.load(event_file)
                              rescue
                                retry
                              end
                            end
                            compare_event_file = Proc.new do |event_file|
                              expect(event_file[:check]).to eq(event[:check])
                              expect(event_file[:client]).to eq(event[:client])
                              async_done
                            end
                            EM.defer(read_event_file, compare_event_file)
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

  it "can consume results with signatures" do
    async_wrapper(30) do
      @server.setup_connections do
        @server.setup_results
        redis.flushdb do
          timer(1) do
            client = client_template
            client[:signature] = "foo"
            redis.set("client:i-424242", Sensu::JSON.dump(client)) do
              result = result_template
              setup_transport do |transport|
                transport.publish(:direct, "results", Sensu::JSON.dump(result))
                timer(1) do
                  redis.sismember("result:i-424242", "test") do |is_member|
                    expect(is_member).to be(false)
                    result[:signature] = "foo"
                    transport.publish(:direct, "results", Sensu::JSON.dump(result))
                    timer(1) do
                      redis.sismember("result:i-424242", "test") do |is_member|
                        expect(is_member).to be(true)
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

  it "can truncate check result output for storage" do
    async_wrapper do
      @server.setup_connections do
        @server.setup_results
        redis.flushdb do
          timer(1) do
            check = check_template
            check[:output] = "foo"
            truncated = @server.truncate_check_output(check)
            expect(truncated[:output]).to eq("foo")
            check[:output] = ""
            truncated = @server.truncate_check_output(check)
            expect(truncated[:output]).to eq("")
            check[:output] = "foo\nbar\nbaz"
            truncated = @server.truncate_check_output(check)
            expect(truncated[:output]).to eq("foo\nbar\nbaz")
            check[:truncate_output] = true
            truncated = @server.truncate_check_output(check)
            expect(truncated[:output]).to eq("foo\n...")
            check.delete(:truncate_output)
            check[:type] = "metric"
            truncated = @server.truncate_check_output(check)
            expect(truncated[:output]).to eq("foo\n...")
            check[:output] = "foo"
            truncated = @server.truncate_check_output(check)
            expect(truncated[:output]).to eq("foo")
            check[:output] = "foo\255"
            truncated = @server.truncate_check_output(check)
            expect(truncated[:output]).to eq("foo")
            check[:output] = ""
            truncated = @server.truncate_check_output(check)
            expect(truncated[:output]).to eq("")
            check[:output] = rand(36**256).to_s(36).rjust(256, '0')
            truncated = @server.truncate_check_output(check)
            expect(truncated[:output]).to eq(check[:output][0..255] + "\n...")
            check[:truncate_output_length] = 10
            truncated = @server.truncate_check_output(check)
            expect(truncated[:output]).to eq(check[:output][0..10] + "\n...")
            check[:truncate_output] = false
            truncated = @server.truncate_check_output(check)
            expect(truncated[:output]).to eq(check[:output])
            client = client_template
            redis.set("client:i-424242", Sensu::JSON.dump(client)) do
              result = result_template
              result[:check][:type] = "metric"
              result[:check][:output] = "foo\nbar\nbaz"
              setup_transport do |transport|
                transport.publish(:direct, "results", Sensu::JSON.dump(result))
              end
              timer(2) do
                redis.sismember("result:i-424242", "test") do |is_member|
                  expect(is_member).to be(true)
                  redis.get("result:i-424242:test") do |result_json|
                    result = Sensu::JSON.load(result_json)
                    expect(result[:output]).to eq("foo\n...")
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

  it "can dynamically create a client for a check source" do
    async_wrapper do
      @server.setup_connections do
        @server.setup_results
        redis.flushdb do
          timer(1) do
            result = result_template
            result[:check][:source] = "i-888888"
            result[:check][:handler] = "debug"
            setup_transport do |transport|
              transport.publish(:direct, "results", Sensu::JSON.dump(result))
            end
            timer(3) do
              redis.sismember("clients", "i-888888") do |exists|
                expect(exists).to be(true)
                redis.get("client:i-888888") do |client_json|
                  client = Sensu::JSON.load(client_json)
                  expect(client[:keepalives]).to be(false)
                  expect(client[:version]).to eq(Sensu::VERSION)
                  expect(client[:timestamp]).to be_within(10).of(epoch)
                  redis.hget("events:i-888888", "test") do |event_json|
                    event = Sensu::JSON.load(event_json)
                    expect(event[:client][:address]).to eq("unknown")
                    expect(event[:client][:subscriptions]).to include("client:i-888888")
                    expect(event[:client][:type]).to eq("proxy")
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

  it "can publish check requests" do
    async_wrapper do
      setup_transport do |transport|
        transport.subscribe(:fanout, "test") do |_, payload|
          check_request = Sensu::JSON.load(payload)
          expect(check_request[:name]).to eq("test")
          expect(check_request[:command]).to eq("echo WARNING && exit 1")
          expect(check_request[:source]).to eq("switch-x")
          expect(check_request[:issued]).to be_within(10).of(epoch)
          async_done
        end
      end
      timer(0.5) do
        @server.setup_transport do
          check = check_template
          check[:subscribers] = ["test"]
          check[:source] = "switch-x"
          @server.publish_check_request(check)
        end
      end
    end
  end

  it "can publish check requests to round-robin subscriptions" do
    async_wrapper do
      setup_transport do |transport|
        transport.subscribe(:direct, "roundrobin:test") do |_, payload|
          check_request = Sensu::JSON.load(payload)
          expect(check_request[:name]).to eq("test")
          expect(check_request[:command]).to eq("echo WARNING && exit 1")
          expect(check_request[:issued]).to be_within(10).of(epoch)
          async_done
        end
      end
      timer(0.5) do
        @server.setup_transport do
          check = check_template
          check[:subscribers] = ["roundrobin:test"]
          @server.publish_check_request(check)
        end
      end
    end
  end

  it "can publish extension check requests" do
    async_wrapper do
      setup_transport do |transport|
        transport.subscribe(:fanout, "test") do |_, payload|
          check_request = Sensu::JSON.load(payload)
          expect(check_request[:name]).to eq("test")
          expect(check_request[:source]).to eq("switch-x")
          expect(check_request[:extension]).to eq("rspec")
          expect(check_request[:issued]).to be_within(10).of(epoch)
          expect(check_request).not_to include(:command)
          async_done
        end
      end
      timer(0.5) do
        @server.setup_transport do
          check = check_template
          check.delete(:command)
          check[:extension] = "rspec"
          check[:subscribers] = ["test"]
          check[:source] = "switch-x"
          @server.publish_check_request(check)
        end
      end
    end
  end

  it "can publish proxy check requests" do
    async_wrapper do
      setup_transport do |transport|
        transport.subscribe(:fanout, "test") do |_, payload|
          check_request = Sensu::JSON.load(payload)
          expect(check_request[:name]).to eq("test")
          expect(check_request[:command]).to eq("echo 127.0.0.1 && exit 1")
          expect(check_request[:source]).to eq("i-424242")
          expect(check_request[:issued]).to be_within(10).of(epoch)
          async_done
        end
        redis.flushdb do
          @server.setup_redis do
            @server.setup_transport do
              @server.setup_keepalives
              timer(1) do
                keepalive = client_template
                keepalive[:timestamp] = epoch
                transport.publish(:direct, "keepalives", Sensu::JSON.dump(keepalive))
                timer(1) do
                  check = check_template
                  check[:command] = "echo :::address::: && exit 1"
                  check[:subscribers] = ["test"]
                  check[:proxy_requests] = {
                    :client_attributes => {
                      :name => "i-424242",
                      :subscriptions => "eval: value.include?('test')"
                    }
                  }
                  @server.create_proxy_check_requests(check)
                end
              end
            end
          end
        end
      end
    end
  end

  it "can publish proxy check requests with splay (using check interval)" do
    async_wrapper do
      setup_transport do |transport|
        transport.subscribe(:fanout, "test") do |_, payload|
          check_request = Sensu::JSON.load(payload)
          expect(check_request[:name]).to eq("test")
          expect(check_request[:command]).to eq("echo 127.0.0.1 && exit 1")
          expect(check_request[:source]).to eq("i-424242")
          expect(check_request[:issued]).to be_within(10).of(epoch)
          async_done
        end
        redis.flushdb do
          @server.setup_redis do
            @server.setup_transport do
              @server.setup_keepalives
              timer(1) do
                keepalive = client_template
                keepalive[:timestamp] = epoch
                transport.publish(:direct, "keepalives", Sensu::JSON.dump(keepalive))
                timer(1) do
                  check = check_template
                  check[:command] = "echo :::address::: && exit 1"
                  check[:subscribers] = ["test"]
                  check[:proxy_requests] = {
                    :splay => true,
                    :splay_coverage => 50,
                    :client_attributes => {
                      :name => "i-424242",
                      :subscriptions => "eval: value.include?('test')"
                    }
                  }
                  @server.create_proxy_check_requests(check)
                end
              end
            end
          end
        end
      end
    end
  end

  it "can publish proxy check requests with splay (using check cron)" do
    async_wrapper do
      setup_transport do |transport|
        transport.subscribe(:fanout, "test") do |_, payload|
          check_request = Sensu::JSON.load(payload)
          expect(check_request[:name]).to eq("test")
          expect(check_request[:command]).to eq("echo 127.0.0.1 && exit 1")
          expect(check_request[:source]).to eq("i-424242")
          expect(check_request[:issued]).to be_within(10).of(epoch)
          async_done
        end
        redis.flushdb do
          @server.setup_redis do
            @server.setup_transport do
              @server.setup_keepalives
              timer(1) do
                keepalive = client_template
                keepalive[:timestamp] = epoch
                transport.publish(:direct, "keepalives", Sensu::JSON.dump(keepalive))
                timer(1) do
                  check = check_template
                  check.delete(:interval)
                  check[:cron] = "* * * * *"
                  check[:command] = "echo :::address::: && exit 1"
                  check[:subscribers] = ["test"]
                  check[:proxy_requests] = {
                    :splay => true,
                    :splay_coverage => 50,
                    :client_attributes => {
                      :name => "i-424242",
                      :subscriptions => "eval: value.include?('test')"
                    }
                  }
                  @server.create_proxy_check_requests(check)
                end
              end
            end
          end
        end
      end
    end
  end

  it "can calculate a check request splay interval" do
    allow(Time).to receive(:now).and_return("1414213569.032")
    check = check_template
    check[:interval] = 60
    expect(@server.calculate_check_request_splay(check)).to eq(17.601)
    check[:interval] = 3600
    expect(@server.calculate_check_request_splay(check)).to eq(3497.601)
  end

  it "can schedule check request publishing" do
    async_wrapper do
      expected = ["tokens", "merger", "source", "cron", "hooked"]
      setup_transport do |transport|
        transport.subscribe(:fanout, "test") do |_, payload|
          check_request = Sensu::JSON.load(payload)
          expect(check_request[:issued]).to be_within(10).of(epoch)
          expect(expected.delete(check_request[:name])).not_to be_nil
          async_done if expected.empty? || expected == ["cron"]
        end
      end
      timer(0.5) do
        @server.setup_transport do
          @server.setup_check_request_publisher
        end
      end
    end
  end

  it "can schedule check request publishing using the cron syntax" do
    async_wrapper do
      check = check_template
      check[:cron] = "* * * * *"
      @server.schedule_checks([check])
      expect(@server.instance_variable_get(:@timers)[:tasks][:check_request_publisher].size).to eq(1)
      async_done
    end
  end

  it "can send a check result" do
    async_wrapper do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:name]).to eq("test")
        async_done
      end
      timer(0.5) do
        @server.setup_connections do
          client = client_template
          check = result_template[:check]
          @server.publish_check_result(client[:name], check)
        end
      end
    end
  end

  it "can determine stale clients and create the appropriate events" do
    async_wrapper do
      @server.setup_connections do
        @server.setup_results
        client1 = client_template
        client1[:name] = "foo"
        client1[:timestamp] = epoch - 60
        client1[:keepalive][:handler] = "debug"
        client1[:keepalive][:contact] = ":::foobar:::"
        client2 = client_template
        client2[:name] = "bar"
        client2[:timestamp] = epoch - 120
        client1[:keepalive][:contacts] = [":::foobar|ops:::"]
        client3 = client_template
        client3[:name] = "qux"
        client3[:keepalives] = false
        client3[:timestamp] = epoch - 1800
        redis.set("client:foo", Sensu::JSON.dump(client1)) do
          redis.sadd("clients", "foo") do
            redis.set("client:bar", Sensu::JSON.dump(client2)) do
              redis.sadd("clients", "bar") do
                redis.set("client:qux", Sensu::JSON.dump(client3)) do
                  redis.sadd("clients", "qux") do
                    timer(1) do
                      @server.determine_stale_clients
                      timer(1) do
                        redis.hget("events:foo", "keepalive") do |event_json|
                          event = Sensu::JSON.load(event_json)
                          expect(event[:check][:output]).to match(/- Unmatched client token\(s\): foobar$/)
                          expect(event[:check][:status]).to eq(1)
                          expect(event[:check][:handler]).to eq("debug")
                          redis.hget("events:bar", "keepalive") do |event_json|
                            event = Sensu::JSON.load(event_json)
                            expect(event[:check][:output]).
                              to match(/^No keepalive sent from client for 12[0-9]+ seconds \(>=120\)$/)
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
    end
  end

  it "can determine stale check results" do
    async_wrapper do
      @server.setup_connections do
        @server.setup_results
        redis.flushdb do
          timer(1) do
            client = client_template
            redis.set("client:i-424242", Sensu::JSON.dump(client)) do
              redis.sadd("clients", "i-424242") do
                result = result_template
                result[:check][:status] = 0
                result[:check][:executed] = epoch - 30
                setup_transport do |transport|
                  transport.publish(:direct, "results", Sensu::JSON.dump(result))
                  result[:check][:name] = "foo"
                  result[:check][:ttl] = 30
                  transport.publish(:direct, "results", Sensu::JSON.dump(result))
                  result[:check][:name] = "bar"
                  result[:check][:ttl] = 60
                  transport.publish(:direct, "results", Sensu::JSON.dump(result))
                  result[:check][:name] = "baz"
                  result[:check][:ttl] = 30
                  result[:check][:ttl_status] = 2
                  transport.publish(:direct, "results", Sensu::JSON.dump(result))
                  timer(2) do
                    @server.determine_stale_check_results(45)
                    timer(2) do
                      redis.hgetall("events:i-424242") do |events|
                        expect(events.size).to eq(2)
                        event = Sensu::JSON.load(events["foo"])
                        expect(event[:check][:output]).to match(/Last check execution was 3[0-9] seconds ago/)
                        expect(event[:check][:status]).to eq(1)
                        expect(event[:check][:interval]).to eq(45)
                        event = Sensu::JSON.load(events["baz"])
                        expect(event[:check][:output]).to match(/Last check execution was 3[0-9] seconds ago/)
                        expect(event[:check][:status]).to eq(2)
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

  it "can skip creating stale check results when client has a keepalive event" do
    async_wrapper do
      redis.flushdb do
        @server.setup_connections do
          @server.setup_results
          client = client_template
          client[:timestamp] = epoch - 120
          redis.set("client:i-424242", Sensu::JSON.dump(client)) do
            redis.sadd("clients", "i-424242") do
              timer(1) do
                @server.determine_stale_clients
                timer(1) do
                  redis.hget("events:i-424242", "keepalive") do |event_json|
                    event = Sensu::JSON.load(event_json)
                    expect(event[:check][:status]).to eq(2)
                    stale_result = result_template
                    stale_result[:check][:status] = 0
                    stale_result[:check][:ttl] = 60
                    stale_result[:check][:executed] = epoch - 1200
                    setup_transport do |transport|
                      transport.publish(:direct, "results", Sensu::JSON.dump(stale_result)) do
                        @server.determine_stale_check_results
                        timer(1) do
                          redis.hexists("events:i-424242", "test") do |ttl_event_exists|
                            expect(ttl_event_exists).to eq(false)
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

  it "can be responsible for all tasks and relinquish them" do
    async_wrapper do
      @server.setup_connections do
        redis.flushdb do
          expect(@server.tasks).to be_empty
          @server.setup_task_elections(0)
          timer(2) do
            expect(@server.tasks).to eq(["check_request_publisher", "client_monitor", "check_result_monitor"])
            @server.relinquish_tasks
            expect(@server.tasks).to be_empty
            async_done
          end
        end
      end
    end
  end

  it "can be responsible for one or more tasks" do
    async_wrapper do
      server1 = Sensu::Server::Process.new(options)
      server2 = Sensu::Server::Process.new(options)
      server1.setup_connections do
        server2.setup_connections do
          redis.flushdb do
            expect(server1.tasks).to be_empty
            expect(server2.tasks).to be_empty
            server1.setup_task_elections(1)
            server2.setup_task_elections(1)
            timer(2) do
              expect(server1.tasks).not_to be_empty
              expect(server2.tasks).not_to be_empty
              expect(server1.tasks - server2.tasks).to eq(server1.tasks)
              async_done
            end
          end
        end
      end
    end
  end

  it "can update the server registry" do
    async_wrapper do
      redis.flushdb do
        @server.setup_connections do
          @server.update_server_registry do
            redis.smembers("servers") do |servers|
              expect(servers).to include(@server.server_id)
              redis.get("server:#{@server.server_id}") do |server_json|
                expect(server_json).to be_kind_of(String)
                server = Sensu::JSON.load(server_json)
                expect(server[:id]).to eq(@server.server_id)
                expect(server[:tasks]).to be_kind_of(Array)
                expect(server[:sensu][:version]).to eq(Sensu::VERSION)
                expect(server[:sensu][:settings][:hexdigest]).to be_kind_of(String)
                expect(server[:tessen][:enabled]).to eq(false)
                expect(server[:timestamp]).to be_within(5).of(Time.now.to_i)
                async_done
              end
            end
          end
        end
      end
    end
  end

  it "can discard oversized transport messages" do
    expect(@server.message_size_ok?("foo")).to eq(true)
    expect(@server.message_size_ok?("0" * 2097152)).to eq(true)
    expect(@server.message_size_ok?("0" * 2097153)).to eq(false)
  end
end
