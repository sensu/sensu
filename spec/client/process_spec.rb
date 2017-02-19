require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/client/process"

describe "Sensu::Client::Process" do
  include Helpers

  before do
    @client = Sensu::Client::Process.new(options)
  end

  it "can connect to the transport" do
    async_wrapper do
      @client.setup_transport do |transport|
        expect(transport.connected?).to eq(true)
        async_done
      end
    end
  end

  it "can send a keepalive" do
    async_wrapper do
      keepalive_queue do |payload|
        keepalive = Sensu::JSON.load(payload)
        expect(keepalive[:name]).to eq("i-424242")
        expect(keepalive[:service][:password]).to eq("REDACTED")
        expect(keepalive[:version]).to eq(Sensu::VERSION)
        expect(keepalive[:timestamp]).to be_within(10).of(epoch)
        async_done
      end
      timer(0.5) do
        @client.setup_transport do
          @client.publish_keepalive
        end
      end
    end
  end

  it "can schedule keepalive publishing" do
    async_wrapper do
      keepalive_queue do |payload|
        keepalive = Sensu::JSON.load(payload)
        expect(keepalive[:name]).to eq("i-424242")
        async_done
      end
      timer(0.5) do
        @client.setup_transport do
          @client.publish_keepalive
        end
      end
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
        @client.setup_transport do
          check = result_template[:check]
          @client.publish_check_result(check)
        end
      end
    end
  end

  it "can send a deregistraion check result" do
    async_wrapper do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:name]).to eq("deregistration")
        expect(result[:check][:status]).to eq(1)
        expect(result[:check][:handler]).to eq("DEREGISTER_HANDLER")
        async_done
      end
      timer(0.5) do
        @client.setup_transport do
          @client.deregister
        end
      end
    end
  end

  it "can execute a check command" do
    async_wrapper do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to eq("WARNING\n")
        expect(result[:check]).to have_key(:executed)
        async_done
      end
      timer(0.5) do
        @client.setup_transport do
          @client.execute_check_command(check_template)
        end
      end
    end
  end

  it "can substitute tokens in a check definition" do
    check = check_template
    check[:command] = "echo :::nested.attribute:::"
    check[:foo] = [":::missing|foo:::"]
    check[:bar] = {
      :baz => ":::missing:::",
      :qux => ":::missing|qux:::",
      :quux => {
        :corge => ":::missing:::",
        :grault => ":::nonexistent:::",
        :garply => ":::missing|garply:::",
        :waldo => ":::name:::"
      }
    }
    substituted, unmatched_tokens = @client.object_substitute_tokens(check, @client.settings[:client])
    expect(substituted[:name]).to eq("test")
    expect(substituted[:command]).to eq("echo true")
    expect(substituted[:foo].first).to eq("foo")
    expect(substituted[:bar][:baz]).to eq("")
    expect(substituted[:bar][:qux]).to eq("qux")
    expect(substituted[:bar][:quux][:corge]).to eq("")
    expect(substituted[:bar][:quux][:grault]).to eq("")
    expect(substituted[:bar][:quux][:garply]).to eq("garply")
    expect(substituted[:bar][:quux][:waldo]).to eq("i-424242")
    expect(unmatched_tokens).to match_array(["missing", "nonexistent"])
  end

  it "can substitute tokens in a command with client attribute values, default values, and execute it" do
    async_wrapper do
      check = check_template
      command = "echo :::nested.attribute|default::: :::missing|default:::"
      command << " :::missing|::: :::nested.attribute:::::::nested.attribute:::"
      command << " :::empty|localhost::: :::empty.hash|localhost:8080:::"
      check[:command] = command
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:command]).to eq(check[:command])
        expect(result[:check][:output]).to eq("true default true:true localhost localhost:8080\n")
        async_done
      end
      timer(0.5) do
        @client.setup_transport do
          @client.execute_check_command(check)
        end
      end
    end
  end

  it "can substitute tokens in a command and handle unmatched tokens" do
    async_wrapper do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to eq("Unmatched client token(s): nonexistent, noexistent.hash, empty.hash")
        async_done
      end
      timer(0.5) do
        @client.setup_transport do
          check = check_template
          check[:command] = "echo :::nonexistent::: :::noexistent.hash::: :::empty.hash:::"
          @client.execute_check_command(check)
        end
      end
    end
  end

  it "can run a check extension" do
    async_wrapper do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to start_with("{")
        expect(result[:check]).to have_key(:executed)
        async_done
      end
      timer(0.5) do
        @client.setup_transport do
          check = {:name => "sensu_gc_metrics"}
          @client.run_check_extension(check)
        end
      end
    end
  end

  it "can receive a check request and execute the check" do
    async_wrapper do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to eq("WARNING\n")
        expect(result[:check][:status]).to eq(1)
        async_done
      end
      timer(0.5) do
        @client.setup_transport do
          @client.setup_subscriptions
          timer(1) do
            setup_transport do |transport|
              transport.publish(:fanout, "test", Sensu::JSON.dump(check_template))
            end
          end
        end
      end
    end
  end

  it "can receive a check request on a round-robin subscription" do
    async_wrapper do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to eq("WARNING\n")
        expect(result[:check][:status]).to eq(1)
        async_done
      end
      timer(0.5) do
        @client.setup_transport do
          @client.setup_subscriptions
          timer(1) do
            setup_transport do |transport|
              transport.publish(:direct, "roundrobin:test", Sensu::JSON.dump(check_template))
            end
          end
        end
      end
    end
  end

  it "can receive a check request and not execute the check due to safe mode" do
    async_wrapper do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to include("safe mode")
        expect(result[:check][:status]).to eq(3)
        async_done
      end
      timer(0.5) do
        @client.safe_mode = true
        @client.setup_transport do
          @client.setup_subscriptions
          timer(1) do
            setup_transport do |transport|
              transport.publish(:fanout, "test", Sensu::JSON.dump(check_template))
            end
          end
        end
      end
    end
  end

  it "can schedule standalone check execution" do
    async_wrapper do
      expected = ["standalone", "sensu_gc_metrics"]
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check]).to have_key(:issued)
        expect(result[:check]).to have_key(:output)
        expect(result[:check]).to have_key(:status)
        expect(expected.delete(result[:check][:name])).not_to be_nil
        if expected.empty?
          async_done
        end
      end
      timer(0.5) do
        @client.setup_transport do
          @client.setup_standalone
        end
      end
    end
  end

  it "can subdue standalone check execution" do
    async_wrapper do
      result_queue do |payload|
        result = Sensu::JSON.load(payload)
        expect(result[:check][:name]).to eq("test")
        async_done
      end
      timer(0.5) do
        @client.setup_transport do
          check = check_template
          checks = [
            check.merge(
              :name => "subdued",
              :subdue => {
                :days => {
                  :all => [
                    {
                      :begin => (Time.now - 3600).strftime("%l:00 %p").strip,
                      :end => (Time.now + 3600).strftime("%l:00 %p").strip
                    }
                  ]
                }
              }
            ),
            check
          ]
          @client.schedule_checks(checks)
        end
      end
    end
  end

  it "can calculate a check execution splay interval" do
    allow(Time).to receive(:now).and_return("1414213569.032")
    check = check_template
    check[:interval] = 60
    expect(@client.calculate_check_execution_splay(check)).to eq(3.321)
    check[:interval] = 3600
    expect(@client.calculate_check_execution_splay(check)).to eq(783.321)
  end

  it "can accept external result input via sockets" do
    async_wrapper do
      @client.setup_transport do
        @client.setup_sockets
        expected = ["tcp", "udp", "http"]
        result_queue do |payload|
          result = Sensu::JSON.load(payload)
          expect(result[:client]).to eq("i-424242")
          expect(expected.delete(result[:check][:name])).not_to be_nil
          if expected.empty?
            async_done
          end
        end
        timer(1) do
          EM::connect("127.0.0.1", 3030, nil) do |socket|
            socket.send_data('{"name": "tcp", "output": "tcp", "status": 1}')
            socket.close_connection_after_writing
          end
          EM::open_datagram_socket("127.0.0.1", 0, nil) do |socket|
            data = '{"name": "udp", "output": "udp", "status": 1}'
            socket.send_datagram(data, "127.0.0.1", 3030)
            socket.close_connection_after_writing
          end
          options = {:body => {:name => "http", :output => "http", :status => 1}}
          http_request(3031, "/results", :post, options)do |http, body|
            expect(http.response_header.status).to eq(202)
            expect(body).to eq({:response => "ok"})
          end
        end
      end
    end
  end
end
