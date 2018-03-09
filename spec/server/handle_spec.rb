require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/server/process"

describe "Sensu::Server::Handle" do
  include Helpers

  before do
    @server = Sensu::Server::Process.new(options)
    settings = Sensu::Settings.get(options)
    @handlers = settings[:handlers]
    @event_id  = event_template[:id]
    @event_data = Sensu::JSON.dump(event_template)
    @extensions = Sensu::Extensions.get(options)
  end

  it "can handle an event handler error" do
    on_error = @server.handler_error(@handlers[:file], @event_data, @event_id)
    expect(on_error.arity).to be(1)
  end

  it "can handle an event with a pipe handler" do
    async_wrapper do
      @server.handle_event(@handlers[:file], @event_data, @event_id)
      timer(1) do
        async_done
      end
    end
    expect(File.exists?("/tmp/sensu_event")).to be(true)
    File.delete("/tmp/sensu_event")
  end

  it "can handle an event with a pipe handler error" do
    async_wrapper do
      @server.handle_event(@handlers[:error], @event_data, @event_id)
      timer(1) do
        async_done
      end
    end
  end

  it "can handle an event with a tcp handler" do
    async_wrapper do
      EM::start_server("127.0.0.1", 1234, Helpers::TestServer) do |server|
        server.expected = @event_data
      end
      @server.handle_event(@handlers[:tcp], @event_data, @event_id)
    end
  end

  it "can handle an event with a udp handler" do
    async_wrapper do
      EM::open_datagram_socket("127.0.0.1", 1234, Helpers::TestServer) do |server|
        server.expected = @event_data
      end
      @server.handle_event(@handlers[:udp], @event_data, @event_id)
    end
  end

  it "can handle an event with a transport handler" do
    async_wrapper do
      setup_transport do |transport|
        transport.subscribe(:direct, "events") do |_, payload|
          expect(Sensu::JSON.load(payload)).to eq(Sensu::JSON.load(@event_data))
          async_done
        end
      end
      timer(0.5) do
        @server.setup_transport do
          @server.handle_event(@handlers[:transport], @event_data, @event_id)
        end
      end
    end
  end

  it "can handle an event with an extension" do
    async_wrapper do
      @server.handle_event(@extensions[:handlers]["debug"], @event_data, @event_id)
      timer(0.5) do
        async_done
      end
    end
  end
end
