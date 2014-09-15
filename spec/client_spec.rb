require File.dirname(__FILE__) + '/helpers.rb'
require 'sensu/client'

describe 'Sensu::Client' do
  include Helpers

  before do
    @client = Sensu::Client.new(options)
  end

  it 'can connect to rabbitmq' do
    async_wrapper do
      @client.setup_transport
      timer(0.5) do
        async_done
      end
    end
  end

  it 'can send a keepalive' do
    async_wrapper do
      keepalive_queue do |queue|
        @client.setup_transport
        @client.publish_keepalive
        queue.subscribe do |payload|
          keepalive = MultiJson.load(payload)
          expect(keepalive[:name]).to eq('i-424242')
          expect(keepalive[:service][:password]).to eq('REDACTED')
          expect(keepalive[:version]).to eq(Sensu::VERSION)
          expect(keepalive[:timestamp]).to be_within(10).of(epoch)
          async_done
        end
      end
    end
  end

  it 'can schedule keepalive publishing' do
    async_wrapper do
      keepalive_queue do |queue|
        @client.setup_transport
        @client.setup_keepalives
        queue.subscribe do |payload|
          keepalive = MultiJson.load(payload)
          expect(keepalive[:name]).to eq('i-424242')
          async_done
        end
      end
    end
  end

  it 'can send a check result' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_transport
        check = result_template[:check]
        @client.publish_result(check)
        queue.subscribe do |payload|
          result = MultiJson.load(payload)
          expect(result[:client]).to eq('i-424242')
          expect(result[:check][:name]).to eq('test')
          async_done
        end
      end
    end
  end

  it 'can execute a check command' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_transport
        @client.execute_check_command(check_template)
        queue.subscribe do |payload|
          result = MultiJson.load(payload)
          expect(result[:client]).to eq('i-424242')
          expect(result[:check][:output]).to eq("WARNING\n")
          expect(result[:check]).to have_key(:executed)
          async_done
        end
      end
    end
  end

  it 'can substitute check command tokens with attributes, default values, and execute it' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_transport
        check = check_template
        command = 'echo :::nested.attribute|default::: :::missing|default:::'
        command << ' :::missing|::: :::nested.attribute:::::::nested.attribute:::'
        command << ' :::empty|localhost::: :::empty.hash|localhost:8080:::'
        check[:command] = command
        @client.execute_check_command(check)
        queue.subscribe do |payload|
          result = MultiJson.load(payload)
          expect(result[:client]).to eq('i-424242')
          expect(result[:check][:output]).to eq("true default true:true localhost localhost:8080\n")
          async_done
        end
      end
    end
  end

  it 'can substitute check command tokens with attributes and handle unmatched tokens' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_transport
        check = check_template
        check[:command] = 'echo :::nonexistent::: :::noexistent.hash::: :::empty.hash:::'
        @client.execute_check_command(check)
        queue.subscribe do |payload|
          result = MultiJson.load(payload)
          expect(result[:client]).to eq('i-424242')
          expect(result[:check][:output]).to eq("Unmatched command tokens: nonexistent, noexistent.hash, empty.hash")
          async_done
        end
      end
    end
  end

  it 'can run a check extension' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_transport
        check = {
          :name => 'sensu_gc_metrics'
        }
        @client.run_check_extension(check)
        queue.subscribe do |payload|
          result = MultiJson.load(payload)
          expect(result[:client]).to eq('i-424242')
          expect(result[:check][:output]).to start_with('{')
          expect(result[:check]).to have_key(:executed)
          async_done
        end
      end
    end
  end

  it 'can setup subscriptions' do
    async_wrapper do
      @client.setup_transport
      @client.setup_subscriptions
      timer(1) do
        amq.fanout('test', :passive => true) do |exchange, declare_ok|
          expect(declare_ok).to be_an_instance_of(AMQ::Protocol::Exchange::DeclareOk)
          expect(exchange.status).to eq(:opening)
          async_done
        end
      end
    end
  end

  it 'can receive a check request and execute the check' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_transport
        @client.setup_subscriptions
        timer(1) do
          amq.fanout('test').publish(MultiJson.dump(check_template))
        end
        queue.subscribe do |payload|
          result = MultiJson.load(payload)
          expect(result[:client]).to eq('i-424242')
          expect(result[:check][:output]).to eq("WARNING\n")
          expect(result[:check][:status]).to eq(1)
          async_done
        end
      end
    end
  end

  it 'can receive a check request and not execute the check due to safe mode' do
    async_wrapper do
      result_queue do |queue|
        @client.safe_mode = true
        @client.setup_transport
        @client.setup_subscriptions
        timer(1) do
          amq.fanout('test').publish(MultiJson.dump(check_template))
        end
        queue.subscribe do |payload|
          result = MultiJson.load(payload)
          expect(result[:client]).to eq('i-424242')
          expect(result[:check][:output]).to include('safe mode')
          expect(result[:check][:status]).to eq(3)
          async_done
        end
      end
    end
  end

  it 'can schedule standalone check execution' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_transport
        @client.setup_standalone
        expected = ['standalone', 'sensu_gc_metrics']
        queue.subscribe do |payload|
          result = MultiJson.load(payload)
          expect(result[:client]).to eq('i-424242')
          expect(result[:check]).to have_key(:issued)
          expect(result[:check]).to have_key(:output)
          expect(result[:check]).to have_key(:status)
          expect(expected.delete(result[:check][:name])).not_to be_nil
          if expected.empty?
            async_done
          end
        end
      end
    end
  end

  describe 'can accept external result input via sockets' do
    it 'with data without length prefix' do
      async_wrapper do
        result_queue do |queue|
          @client.setup_transport
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
          queue.subscribe do |payload|
            result = MultiJson.load(payload)
            expect(result[:client]).to eq('i-424242')
            expect(expected.delete(result[:check][:name])).not_to be_nil
            if expected.empty?
              async_done
            end
          end
        end
      end
    end
    it 'with data with length prefix' do
      async_wrapper do
        result_queue do |queue|
          @client.setup_transport
          @client.setup_sockets
          timer(1) do
            EM::connect('127.0.0.1', 3030, nil) do |socket|
              data = '{"name": "tcp", "output": "tcp", "status": 1}'
              socket.send_data("#{data.length}\n#{data}")
              socket.close_connection_after_writing
            end
            EM::open_datagram_socket('127.0.0.1', 0, nil) do |socket|
              data = '{"name": "udp", "output": "udp", "status": 1}'
              socket.send_datagram("#{data.length}\n#{data}", '127.0.0.1', 3030)
              socket.close_connection_after_writing
            end
          end
          expected = ['tcp', 'udp']
          queue.subscribe do |payload|
            result = MultiJson.load(payload)
            expect(result[:client]).to eq('i-424242')
            expect(expected.delete(result[:check][:name])).not_to be_nil
            if expected.empty?
              async_done
            end
          end
        end
      end
    end
  end
end
