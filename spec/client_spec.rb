require File.dirname(__FILE__) + '/../lib/sensu/client.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::Client' do
  include Helpers

  before do
    @client = Sensu::Client.new(options)
  end

  it 'can connect to rabbitmq' do
    async_wrapper do
      @client.setup_rabbitmq
      async_done
    end
  end

  it 'can send a keepalive' do
    async_wrapper do
      keepalive_queue do |queue|
        @client.setup_rabbitmq
        @client.publish_keepalive
        queue.subscribe do |payload|
          keepalive = Oj.load(payload)
          keepalive[:name].should eq('i-424242')
          keepalive[:service][:password].should eq('REDACTED')
          async_done
        end
      end
    end
  end

  it 'can schedule keepalive publishing' do
    async_wrapper do
      keepalive_queue do |queue|
        @client.setup_rabbitmq
        @client.setup_keepalives
        queue.subscribe do |payload|
          keepalive = Oj.load(payload)
          keepalive[:name].should eq('i-424242')
          async_done
        end
      end
    end
  end

  it 'can send a check result' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_rabbitmq
        check = result_template[:check]
        @client.publish_result(check)
        queue.subscribe do |payload|
          result = Oj.load(payload)
          result[:client].should eq('i-424242')
          result[:check][:name].should eq('foobar')
          async_done
        end
      end
    end
  end

  it 'can execute a check command' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_rabbitmq
        @client.execute_check_command(check_template)
        queue.subscribe do |payload|
          result = Oj.load(payload)
          result[:client].should eq('i-424242')
          result[:check][:output].should eq("WARNING\n")
          result[:check].should have_key(:executed)
          async_done
        end
      end
    end
  end

  it 'can substitute check command tokens with attributes, default values, and execute it' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_rabbitmq
        check = check_template
        check[:command] = 'echo :::nested.attribute|default::: :::missing|default::: :::missing|:::'
        @client.execute_check_command(check)
        queue.subscribe do |payload|
          result = Oj.load(payload)
          result[:client].should eq('i-424242')
          result[:check][:output].should eq("true default\n")
          async_done
        end
      end
    end
  end

  it 'can run a check extension' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_rabbitmq
        check = {
          :name => 'sensu_gc_metrics'
        }
        @client.run_check_extension(check)
        queue.subscribe do |payload|
          result = Oj.load(payload)
          result[:client].should eq('i-424242')
          result[:check][:output].should start_with('{')
          result[:check].should have_key(:executed)
          async_done
        end
      end
    end
  end

  it 'can setup subscriptions' do
    async_wrapper do
      @client.setup_rabbitmq
      @client.setup_subscriptions
      timer(1) do
        amq.fanout('test', :passive => true) do |exchange, declare_ok|
          declare_ok.should be_an_instance_of(AMQ::Protocol::Exchange::DeclareOk)
          exchange.status.should eq(:opening)
          async_done
        end
      end
    end
  end

  it 'can receive a check request and execute the check' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_rabbitmq
        @client.setup_subscriptions
        timer(1) do
          amq.fanout('test').publish(Oj.dump(check_template))
        end
        queue.subscribe do |payload|
          result = Oj.load(payload)
          result[:client].should eq('i-424242')
          result[:check][:output].should eq("WARNING\n")
          result[:check][:status].should eq(1)
          async_done
        end
      end
    end
  end

  it 'can receive a check request and not execute the check due to safe mode' do
    async_wrapper do
      result_queue do |queue|
        @client.safe_mode = true
        @client.setup_rabbitmq
        @client.setup_subscriptions
        timer(1) do
          amq.fanout('test').publish(Oj.dump(check_template))
        end
        queue.subscribe do |payload|
          result = Oj.load(payload)
          result[:client].should eq('i-424242')
          result[:check][:output].should include('safe mode')
          result[:check][:status].should eq(3)
          async_done
        end
      end
    end
  end

  it 'can schedule standalone check execution' do
    async_wrapper do
      result_queue do |queue|
        @client.setup_rabbitmq
        @client.setup_standalone
        expected = ['standalone', 'sensu_gc_metrics']
        queue.subscribe do |payload|
          result = Oj.load(payload)
          result[:client].should eq('i-424242')
          result[:check].should have_key(:issued)
          result[:check].should have_key(:output)
          result[:check].should have_key(:status)
          expected.delete(result[:check][:name]).should_not be_nil
          if expected.empty?
            async_done
          end
        end
      end
    end
  end

  it 'can accept external result input via sockets' do
    async_wrapper do
      result_queue do |queue|
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
        queue.subscribe do |payload|
          result = Oj.load(payload)
          result[:client].should eq('i-424242')
          expected.delete(result[:check][:name]).should_not be_nil
          if expected.empty?
            async_done
          end
        end
      end
    end
  end
end
