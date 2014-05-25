require File.dirname(__FILE__) + '/helpers.rb'
require 'sensu/server'

describe 'Sensu::Server' do
  include Helpers

  before do
    @server = Sensu::Server.new(options)
  end

  it 'can connect to redis' do
    async_wrapper do
      @server.setup_redis
      timer(0.5) do
        async_done
      end
    end
  end

  it 'can connect to rabbitmq' do
    async_wrapper do
      @server.setup_transport
      timer(0.5) do
        async_done
      end
    end
  end

  it 'can consume client keepalives' do
    async_wrapper do
      @server.setup_redis
      @server.setup_transport
      @server.setup_keepalives
      keepalive = client_template
      keepalive[:timestamp] = epoch
      redis.flushdb do
        timer(1) do
          amq.direct('keepalives').publish(MultiJson.dump(keepalive))
          timer(1) do
            redis.sismember('clients', 'i-424242') do |exists|
              expect(exists).to be_true
              redis.get('client:i-424242') do |client_json|
                client = MultiJson.load(client_json)
                expect(client).to eq(keepalive)
                async_done
              end
            end
          end
        end
      end
    end
  end

  it 'can determine if an action is subdued' do
    expect(@server.action_subdued?(Hash.new)).to be_false
    condition = {
      :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
      :end => (Time.now + 3600).strftime('%l:00 %p').strip
    }
    expect(@server.action_subdued?(condition)).to be_true
    condition = {
      :begin => (Time.now + 3600).strftime('%l:00 %p').strip,
      :end => (Time.now + 7200).strftime('%l:00 %p').strip
    }
    expect(@server.action_subdued?(condition)).to be_false
    condition = {
      :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
      :end => (Time.now - 7200).strftime('%l:00 %p').strip
    }
    expect(@server.action_subdued?(condition)).to be_true
    condition = {
      :begin => (Time.now + 3600).strftime('%l:00 %p').strip,
      :end => (Time.now - 7200).strftime('%l:00 %p').strip
    }
    expect(@server.action_subdued?(condition)).to be_false
    condition = {
      :days => [
        Time.now.strftime('%A'),
        'wednesday'
      ]
    }
    expect(@server.action_subdued?(condition)).to be_true
    condition = {
      :days => [
        (Time.now + 86400).strftime('%A'),
        (Time.now + 172800).strftime('%A')
      ]
    }
    expect(@server.action_subdued?(condition)).to be_false
    condition = {
      :days => %w[sunday monday tuesday wednesday thursday friday saturday],
      :exceptions => [
        {
          :begin => (Time.now + 3600).rfc2822,
          :end => (Time.now + 7200)
        }
      ]
    }
    expect(@server.action_subdued?(condition)).to be_true
    condition = {
      :days => %w[sunday monday tuesday wednesday thursday friday saturday],
      :exceptions => [
        {
          :begin => (Time.now - 3600).rfc2822,
          :end => (Time.now + 3600).rfc2822
        }
      ]
    }
    expect(@server.action_subdued?(condition)).to be_false
    check = {
      :subdue => {
        :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
        :end => (Time.now + 3600).strftime('%l:00 %p').strip
      }
    }
    expect(@server.check_request_subdued?(check)).to be_false
    handler = Hash.new
    expect(@server.handler_subdued?(handler, check)).to be_true
    check[:subdue][:at] = 'publisher'
    expect(@server.check_request_subdued?(check)).to be_true
    expect(@server.handler_subdued?(handler, check)).to be_false
    handler = {
      :subdue => {
        :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
        :end => (Time.now + 3600).strftime('%l:00 %p').strip
      }
    }
    expect(@server.handler_subdued?(handler, check)).to be_true
  end

  it 'can determine if filter attributes match an event' do
    attributes = {
      :occurrences => 1
    }
    event = event_template
    expect(@server.filter_attributes_match?(attributes, event)).to be_true
    event[:occurrences] = 2
    expect(@server.filter_attributes_match?(attributes, event)).to be_false
    attributes[:occurrences] = "eval: value == 1 || value % 60 == 0"
    event[:occurrences] = 1
    expect(@server.filter_attributes_match?(attributes, event)).to be_true
    event[:occurrences] = 2
    expect(@server.filter_attributes_match?(attributes, event)).to be_false
    event[:occurrences] = 120
    expect(@server.filter_attributes_match?(attributes, event)).to be_true
  end

  it 'can determine if a event is to be filtered' do
    event = event_template
    event[:client][:environment] = 'production'
    expect(@server.event_filtered?('production', event)).to be_false
    expect(@server.event_filtered?('development', event)).to be_true
  end

  it 'can derive handlers from a handler list' do
    handler_list = ['default', 'file', 'missing']
    handlers = @server.derive_handlers(handler_list)
    expect(handlers.first).to be_an_instance_of(Sensu::Extension::Debug)
    expected = {
      :name => 'file',
      :type => 'pipe',
      :command => 'cat > /tmp/sensu_event'
    }
    expect(handlers.last).to eq(expected)
  end

  it 'can determine handlers for an event' do
    event = event_template
    event[:client][:environment] = 'production'
    event[:check][:handlers] = ['file', 'filtered', 'severities']
    expected = [
      {
        :name => 'file',
        :type => 'pipe',
        :command => 'cat > /tmp/sensu_event'
      }
    ]
    expect(@server.event_handlers(event)).to eq(expected)
    event[:client][:environment] = 'development'
    expected << {
      :name => 'filtered',
      :type => 'pipe',
      :command => 'cat > /tmp/sensu_event',
      :filter => 'development'
    }
    expect(@server.event_handlers(event)).to eq(expected)
    event[:check][:status] = 2
    expected << {
      :name => 'severities',
      :type => 'pipe',
      :command => 'cat > /tmp/sensu_event',
      :severities => [
        'critical',
        'unknown'
      ]
    }
    expect(@server.event_handlers(event)).to eq(expected)
    event[:check][:status] = 42
    expect(@server.event_handlers(event)).to eq(expected)
    event[:check][:status] = 0
    event[:check][:history] = [2, 0]
    event[:action] = :resolve
    expect(@server.event_handlers(event)).to eq(expected)
    event[:check][:history] = [0, 2, 1, 0]
    expect(@server.event_handlers(event)).to eq(expected)
    event[:action] = :flapping
    expect(@server.event_handlers(event)).to be_empty
    event[:check].delete(:handlers)
    event[:check][:handler] = 'severities'
    event[:check][:history] = [1, 0]
    event[:action] = :resolve
    expect(@server.event_handlers(event)).to be_empty
    event[:check][:handler] = 'flapping'
    expected = [
      {
        :name => 'flapping',
        :type => 'pipe',
        :command => 'cat > /tmp/sensu_event',
        :handle_flapping => true
      }
    ]
    expect(@server.event_handlers(event)).to eq(expected)
  end

  it 'can mutate event data' do
    async_wrapper do
      event = event_template
      @server.mutate_event_data('unknown', event) do |event_data|
        raise 'should never get here'
      end
      @server.mutate_event_data('explode', event) do |event_data|
        raise 'should never get here'
      end
      @server.mutate_event_data('fail', event) do |event_data|
        raise 'should never get here'
      end
      @server.mutate_event_data(nil, event) do |event_data|
        expect(event_data).to eq(MultiJson.dump(event))
        @server.mutate_event_data('only_check_output', event) do |event_data|
          expect(event_data).to eq('WARNING')
          @server.mutate_event_data('tag', event) do |event_data|
            expect(MultiJson.load(event_data)).to include(:mutated)
            @server.mutate_event_data('settings', event) do |event_data|
              expect(event_data).to eq('true')
              async_done
            end
          end
        end
      end
    end
  end

  it 'can handle an event with a pipe handler' do
    event = event_template
    event[:check][:handler] = 'file'
    async_wrapper do
      @server.handle_event(event)
      timer(1) do
        async_done
      end
    end
    expect(File.exists?('/tmp/sensu_event')).to be_true
    File.delete('/tmp/sensu_event')
  end

  it 'can handle an event with a tcp handler' do
    async_wrapper do
      event = event_template
      event[:check][:handler] = 'tcp'
      EM::start_server('127.0.0.1', 1234, Helpers::TestServer) do |server|
        server.expected = MultiJson.dump(event)
      end
      @server.handle_event(event)
    end
  end

  it 'can handle an event with a udp handler' do
    async_wrapper do
      event = event_template
      event[:check][:handler] = 'udp'
      EM::open_datagram_socket('127.0.0.1', 1234, Helpers::TestServer) do |server|
        server.expected = MultiJson.dump(event)
      end
      @server.handle_event(event)
    end
  end

  it 'can handle an event with a amqp handler' do
    async_wrapper do
      @server.setup_transport
      event = event_template
      event[:check][:handler] = 'transport'
      amq.direct('events') do
        queue = amq.queue('', :auto_delete => true).bind('events') do
          @server.handle_event(event)
        end
        queue.subscribe do |payload|
          expect(payload).to eq(MultiJson.dump(event))
          async_done
        end
      end
    end
  end

  it 'can handle an event with an extension' do
    async_wrapper do
      event = event_template
      event[:check][:handler] = 'debug'
      @server.handle_event(event)
      timer(0.5) do
        async_done
      end
    end
  end

  it 'can aggregate results' do
    async_wrapper do
      @server.setup_redis
      timestamp = epoch
      clients = ['foo', 'bar', 'baz', 'qux']
      redis.flushdb do
        clients.each_with_index do |client_name, index|
          result = result_template
          result[:client] = client_name
          result[:check][:status] = index
          @server.aggregate_result(result)
        end
        timer(2) do
          result_set = 'test:' + timestamp.to_s
          redis.sismember('aggregates', 'test') do |exists|
            expect(exists).to be_true
            redis.sismember('aggregates:test', timestamp.to_s) do |exists|
              expect(exists).to be_true
              redis.hgetall('aggregate:' + result_set) do |aggregate|
                expect(aggregate['total']).to eq('4')
                expect(aggregate['ok']).to eq('1')
                expect(aggregate['warning']).to eq('1')
                expect(aggregate['critical']).to eq('1')
                expect(aggregate['unknown']).to eq('1')
                redis.hgetall('aggregation:' + result_set) do |aggregation|
                  clients.each do |client_name|
                    expect(aggregation).to include(client_name)
                  end
                  async_done
                end
              end
            end
          end
        end
      end
    end
  end

  it 'can process results with flap detection' do
    async_wrapper do
      @server.setup_redis
      redis.flushdb do
        client = client_template
        redis.set('client:i-424242', MultiJson.dump(client)) do
          26.times do |index|
            result = result_template
            result[:check][:low_flap_threshold] = 5
            result[:check][:high_flap_threshold] = 20
            result[:check][:status] = index % 2
            @server.process_result(result)
          end
          timer(1) do
            redis.llen('history:i-424242:test') do |length|
              expect(length).to eq(21)
              redis.hget('events:i-424242', 'test') do |event_json|
                event = MultiJson.load(event_json)
                expect(event[:action]).to eq('flapping')
                expect(event[:occurrences]).to be_within(2).of(1)
                async_done
              end
            end
          end
        end
      end
    end
  end

  it 'can consume results' do
    async_wrapper do
      @server.setup_transport
      @server.setup_redis
      @server.setup_results
      redis.flushdb do
        timer(1) do
          client = client_template
          redis.set('client:i-424242', MultiJson.dump(client)) do
            result = result_template
            amq.direct('results').publish(MultiJson.dump(result))
            timer(1) do
              redis.hget('events:i-424242', 'test') do |event_json|
                event = MultiJson.load(event_json)
                expect(event[:id]).to be_kind_of(String)
                expect(event[:check][:status]).to eq(1)
                expect(event[:occurrences]).to eq(1)
                latest_event_file = IO.read('/tmp/sensu-event.json')
                expect(MultiJson.load(latest_event_file)).to eq(event)
                async_done
              end
            end
          end
        end
      end
    end
  end

  it 'can publish check requests' do
    async_wrapper do
      @server.setup_transport
      amq.fanout('test') do
        check = check_template
        check[:subscribers] = ['test']
        queue = amq.queue('', :auto_delete => true).bind('test') do
          @server.publish_check_request(check)
        end
        queue.subscribe do |payload|
          check_request = MultiJson.load(payload)
          expect(check_request[:name]).to eq('test')
          expect(check_request[:command]).to eq('echo WARNING && exit 1')
          expect(check_request[:issued]).to be_within(10).of(epoch)
          async_done
        end
      end
    end
  end

  it 'can schedule check request publishing' do
    async_wrapper do
      @server.setup_transport
      @server.setup_publisher
      amq.fanout('test') do
        expected = ['tokens', 'merger', 'sensu_cpu_time']
        amq.queue('', :auto_delete => true).bind('test').subscribe do |payload|
          check_request = MultiJson.load(payload)
          expect(check_request[:issued]).to be_within(10).of(epoch)
          expect(expected.delete(check_request[:name])).not_to be_nil
          if expected.empty?
            async_done
          end
        end
      end
    end
  end

  it 'can send a check result' do
    async_wrapper do
      result_queue do |queue|
        @server.setup_transport
        client = client_template
        check = result_template[:check]
        @server.publish_result(client, check)
        queue.subscribe do |payload|
          result = MultiJson.load(payload)
          expect(result[:client]).to eq('i-424242')
          expect(result[:check][:name]).to eq('test')
          async_done
        end
      end
    end
  end

  it 'can determine stale clients and create the appropriate events' do
    async_wrapper do
      @server.setup_redis
      @server.setup_transport
      @server.setup_results
      client1 = client_template
      client1[:name] = 'foo'
      client1[:timestamp] = epoch - 60
      client1[:keepalive][:handler] = 'debug'
      client2 = client_template
      client2[:name] = 'bar'
      client2[:timestamp] = epoch - 120
      redis.set('client:foo', MultiJson.dump(client1)) do
        redis.sadd('clients', 'foo') do
          redis.set('client:bar', MultiJson.dump(client2)) do
            redis.sadd('clients', 'bar') do
              @server.determine_stale_clients
              timer(1) do
                redis.hget('events:foo', 'keepalive') do |event_json|
                  event = MultiJson.load(event_json)
                  expect(event[:check][:status]).to eq(1)
                  expect(event[:check][:handler]).to eq('debug')
                  redis.hget('events:bar', 'keepalive') do |event_json|
                    event = MultiJson.load(event_json)
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

  it 'can prune aggregations' do
    async_wrapper do
      @server.setup_redis
      redis.flushdb do
        client = client_template
        redis.set('client:i-424242', MultiJson.dump(client)) do
          timestamp = epoch - 26
          26.times do |index|
            result = result_template
            result[:check][:issued] = timestamp + index
            result[:check][:status] = index
            @server.aggregate_result(result)
          end
          timer(1) do
            redis.smembers('aggregates:test') do |aggregates|
              aggregates.sort!
              expect(aggregates.size).to eq(26)
              oldest = aggregates.shift
              @server.prune_aggregations
              timer(1) do
                redis.smembers('aggregates:test') do |aggregates|
                  expect(aggregates.size).to eq(20)
                  expect(aggregates).not_to include(oldest)
                  result_set = 'test:' + oldest
                  redis.exists('aggregate:' + result_set) do |exists|
                    expect(exists).to be_false
                    redis.exists('aggregation:' + result_set) do |exists|
                      expect(exists).to be_false
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

  it 'can be the master and resign' do
    async_wrapper do
      @server.setup_redis
      @server.setup_transport
      redis.flushdb do
        @server.request_master_election
        timer(1) do
          expect(@server.is_master).to be_true
          @server.resign_as_master do
            expect(@server.is_master).to be_false
            async_done
          end
        end
      end
    end
  end

  it 'can be the only master' do
    async_wrapper do
      server1 = @server.clone
      server2 = @server.clone
      server1.setup_redis
      server2.setup_redis
      server1.setup_transport
      server2.setup_transport
      redis.flushdb do
        redis.set('lock:master', epoch - 60) do
          server1.setup_master_monitor
          server2.setup_master_monitor
          timer(1) do
            expect([server1.is_master, server2.is_master].uniq.size).to eq(2)
            async_done
          end
        end
      end
    end
  end
end
