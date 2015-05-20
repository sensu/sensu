require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/client/process"

describe "Sensu::Client::Process" do
  include Helpers

  before do
    @client = Sensu::Client::Process.new(options)
  end

  it "can connect to the transport" do
    async_wrapper do
      @client.setup_transport
      timer(0.5) do
        async_done
      end
    end
  end

  it "can send a keepalive" do
    async_wrapper do
      keepalive_queue do |payload|
        keepalive = MultiJson.load(payload)
        expect(keepalive[:name]).to eq("i-424242")
        expect(keepalive[:service][:password]).to eq("REDACTED")
        expect(keepalive[:version]).to eq(Sensu::VERSION)
        expect(keepalive[:timestamp]).to be_within(10).of(epoch)
        async_done
      end
      timer(0.5) do
        @client.setup_transport
        @client.publish_keepalive
      end
    end
  end

  it "can schedule keepalive publishing" do
    async_wrapper do
      keepalive_queue do |payload|
        keepalive = MultiJson.load(payload)
        expect(keepalive[:name]).to eq("i-424242")
        async_done
      end
      timer(0.5) do
        @client.setup_transport
        @client.publish_keepalive
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
        @client.setup_transport
        check = result_template[:check]
        @client.publish_check_result(check)
      end
    end
  end

  it "can execute a check command" do
    async_wrapper do
      result_queue do |payload|
        result = MultiJson.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to eq("WARNING\n")
        expect(result[:check]).to have_key(:executed)
        async_done
      end
      timer(0.5) do
        @client.setup_transport
        @client.execute_check_command(check_template)
      end
    end
  end

  it "can substitute check command tokens with attributes, default values, and execute it" do
    async_wrapper do
      result_queue do |payload|
        result = MultiJson.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to eq("true default true:true localhost localhost:8080\n")
        async_done
      end
      timer(0.5) do
        @client.setup_transport
        check = check_template
        command = "echo :::nested.attribute|default::: :::missing|default:::"
        command << " :::missing|::: :::nested.attribute:::::::nested.attribute:::"
        command << " :::empty|localhost::: :::empty.hash|localhost:8080:::"
        check[:command] = command
        @client.execute_check_command(check)
      end
    end
  end

  it "can substitute check command tokens with attributes and handle unmatched tokens" do
    async_wrapper do
      result_queue do |payload|
        result = MultiJson.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to eq("Unmatched command tokens: nonexistent, noexistent.hash, empty.hash")
        async_done
      end
      timer(0.5) do
        @client.setup_transport
        check = check_template
        check[:command] = "echo :::nonexistent::: :::noexistent.hash::: :::empty.hash:::"
        @client.execute_check_command(check)
      end
    end
  end

  it "can run a check extension" do
    async_wrapper do
      result_queue do |payload|
        result = MultiJson.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to start_with("{")
        expect(result[:check]).to have_key(:executed)
        async_done
      end
      timer(0.5) do
        @client.setup_transport
        check = {:name => "sensu_gc_metrics"}
        @client.run_check_extension(check)
      end
    end
  end

  it "can receive a check request and execute the check" do
    async_wrapper do
      result_queue do |payload|
        result = MultiJson.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to eq("WARNING\n")
        expect(result[:check][:status]).to eq(1)
        async_done
      end
      timer(0.5) do
        @client.setup_transport
        @client.setup_subscriptions
        timer(1) do
          transport.publish(:fanout, "test", MultiJson.dump(check_template))
        end
      end
    end
  end

  it "can receive a check request on a round-robin subscription" do
    async_wrapper do
      result_queue do |payload|
        result = MultiJson.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to eq("WARNING\n")
        expect(result[:check][:status]).to eq(1)
        async_done
      end
      timer(0.5) do
        @client.setup_transport
        @client.setup_subscriptions
        timer(1) do
          transport.publish(:direct, "roundrobin:test", MultiJson.dump(check_template))
        end
      end
    end
  end

  it "can receive a check request and not execute the check due to safe mode" do
    async_wrapper do
      result_queue do |payload|
        result = MultiJson.load(payload)
        expect(result[:client]).to eq("i-424242")
        expect(result[:check][:output]).to include("safe mode")
        expect(result[:check][:status]).to eq(3)
        async_done
      end
      timer(0.5) do
        @client.safe_mode = true
        @client.setup_transport
        @client.setup_subscriptions
        timer(1) do
          transport.publish(:fanout, "test", MultiJson.dump(check_template))
        end
      end
    end
  end

  it "can schedule standalone check execution" do
    async_wrapper do
      expected = ["standalone", "sensu_gc_metrics"]
      result_queue do |payload|
        result = MultiJson.load(payload)
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
        @client.setup_transport
        @client.setup_standalone
      end
    end
  end

  it "can calculate a check execution splay interval" do
    allow(Time).to receive(:now).and_return("1414213569.032")
    check = check_template
    check[:interval] = 60
    expect(@client.calculate_execution_splay(check)).to eq(3.321)
    check[:interval] = 3600
    expect(@client.calculate_execution_splay(check)).to eq(783.321)
  end

  it "can accept external result input via sockets" do
    async_wrapper do
      @client.setup_transport
      @client.setup_sockets
      expected = ["tcp", "udp"]
      result_queue do |payload|
        result = MultiJson.load(payload)
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
      end
    end
  end
end
