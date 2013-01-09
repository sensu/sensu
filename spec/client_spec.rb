require File.dirname(__FILE__) + '/../lib/sensu/client.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe "Sensu::Client" do
  include Helpers

  before do
    options
    @client = Sensu::Client.new(@options)
  end

  it "can connect to rabbitmq" do
    async_wrapper do
      @client.setup_rabbitmq
      async_done
    end
  end

  it "can send a keepalive" do
    async_wrapper do
      @client.setup_rabbitmq
      @client.publish_keepalive
      amq.queue('keepalives').subscribe do |headers, payload|
        keepalive = JSON.parse(payload, :symbolize_names => true)
        keepalive[:name].should eq('i-424242')
        async_done
      end
    end
  end

  it "can schedule keepalive publishing" do
    async_wrapper do
      @client.setup_rabbitmq
      @client.setup_keepalives
      amq.queue('keepalives').subscribe do |headers, payload|
        keepalive = JSON.parse(payload, :symbolize_names => true)
        keepalive[:name].should eq('i-424242')
        async_done
      end
    end
  end

  it "can send a check result" do
    async_wrapper do
      @client.setup_rabbitmq
      check = {
        :name => 'foo',
        :command => 'echo -n foobar',
        :issued => epoch,
        :output => 'bar',
        :status => 2
      }
      @client.publish_result(check)
      result_queue = amq.queue('results')
      result_queue.subscribe do |headers, payload|
        result = JSON.parse(payload, :symbolize_names => true)
        result[:client].should eq('i-424242')
        result[:check][:name].should eq('foo')
        async_done
      end
    end
  end

  it "can execute a check" do
    async_wrapper do
      @client.setup_rabbitmq
      check = {
        :name => 'foo',
        :command => 'echo -n foobar',
        :issued => epoch
      }
      @client.execute_check(check)
      amq.queue('results').subscribe do |headers, payload|
        result = JSON.parse(payload, :symbolize_names => true)
        result[:client].should eq('i-424242')
        result[:check][:output].should eq('foobar')
        async_done
      end
    end
  end

  it "can setup subscriptions" do
    async_wrapper do
      @client.setup_rabbitmq
      @client.setup_subscriptions
      amq.fanout('test', :passive => true) do |exchange, declare_ok|
        declare_ok.should be_an_instance_of(AMQ::Protocol::Exchange::DeclareOk)
        exchange.status.should eq(:opening)
        async_done
      end
    end
  end

  it "can receive a check request and execute the check (with tokens)" do
    async_wrapper do
      @client.setup_rabbitmq
      @client.setup_subscriptions
      check_request = {
        :name => 'tokens',
        :issued => epoch
      }
      amq.fanout('test').publish(check_request.to_json)
      amq.queue('results').subscribe do |headers, payload|
        result = JSON.parse(payload, :symbolize_names => true)
        result[:client].should eq('i-424242')
        result[:check][:output].should eq('i-424242 true')
        result[:check][:status].should eq(2)
        async_done
      end
    end
  end

  it "can schedule standalone check execution" do
    async_wrapper do
      @client.setup_rabbitmq
      @client.setup_standalone
      amq.queue('results').subscribe do |headers, payload|
        result = JSON.parse(payload, :symbolize_names => true)
        result[:client].should eq('i-424242')
        result[:check][:name].should eq('standalone')
        result[:check][:output].should eq('foobar')
        result[:check][:status].should eq(1)
        async_done
      end
    end
  end

  it "can accept external result input via sockets" do
    async_wrapper do
      @client.setup_rabbitmq
      @client.setup_sockets
      timer(1) do
        EM::connect('127.0.0.1', 3030, nil) do |socket|
          socket.send_data('{"name": "tcp", "output": "tcp", "status": 1}')
          socket.close_connection_after_writing
        end
        EM::open_datagram_socket('127.0.0.1', 0, nil) do |socket|
          data = '{"name": "udp", "output": "udp", "status": 1}'
          socket.send_datagram(data, '127.0.0.1', 3030)
          socket.close_connection_after_writing
        end
      end
      expected = ['tcp', 'udp']
      amq.queue('results').subscribe do |headers, payload|
        result = JSON.parse(payload, :symbolize_names => true)
        result[:client].should eq('i-424242')
        expected.delete(result[:check][:name]).should_not be_nil
        if expected.empty?
          async_done
        end
      end
    end
  end
end
