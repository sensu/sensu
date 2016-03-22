require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/server/socket"

describe "Sensu::Server::Socket" do
  include Helpers

  before do
    @event_data = Sensu::JSON.dump(event_template)
  end

  it "can send data to a listening socket" do
    async_wrapper do
      EM::start_server("127.0.0.1", 1234, Helpers::TestServer) do |server|
        server.expected = @event_data
      end
      EM::connect("127.0.0.1", 1234, Sensu::Server::Socket) do |socket|
        socket.on_success = Proc.new {}
        socket.on_error = Proc.new {}
        socket.send_data(@event_data)
        socket.close_connection_after_writing
      end
    end
  end

  it "can fail to connect to a socket" do
    async_wrapper do
      EM::connect("127.0.0.1", 1234, Sensu::Server::Socket) do |socket|
        socket.on_success = Proc.new {}
        socket.on_error = Proc.new do |error|
          expect(error.to_s).to eq("failed to connect to socket")
          async_done
        end
        socket.send_data(@event_data)
        socket.close_connection_after_writing
      end
    end
  end

  it "can timeout while sending data to a socket" do
    async_wrapper do
      EM::start_server("127.0.0.1", 1234, Helpers::TestServer)
      EM::connect("127.0.0.1", 1234, Sensu::Server::Socket) do |socket|
        socket.on_success = Proc.new {}
        socket.on_error = Proc.new do |error|
          expect(error.to_s).to eq("socket timeout")
          async_done
        end
        socket.set_timeout(1)
        socket.send_data(@event_data)
      end
    end
  end
end
