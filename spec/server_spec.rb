require File.dirname(__FILE__) + '/../lib/sensu/server.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::Server' do
  include Helpers

  before do
    @server = Sensu::Server.new(options)
  end

  it 'can connect to redis' do
    async_wrapper do
      @server.setup_redis
      async_done
    end
  end

  it 'can connect to rabbitmq' do
    async_wrapper do
      @server.setup_rabbitmq
      async_done
    end
  end

  it 'can consume client keepalives' do
    async_wrapper do
      @server.setup_redis
      @server.setup_rabbitmq
      @server.setup_keepalives
      keepalive = client_template
      keepalive[:timestamp] = epoch
      redis.flushdb do
        amq.direct('keepalives').publish(Oj.dump(keepalive))
        timer(1) do
          redis.sismember('clients', 'i-424242') do |exists|
            exists.should be_true
            redis.get('client:i-424242') do |client_json|
              client = Oj.load(client_json)
              client.should eq(keepalive)
              async_done
            end
          end
        end
      end
    end
  end

  it 'can determine if an action is subdued' do
    @server.action_subdued?(Hash.new).should be_false
    check = {
      :subdue => {
        :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
        :end => (Time.now + 3600).strftime('%l:00 %p').strip
      }
    }
    @server.action_subdued?(check).should be_false
    handler = Hash.new
    @server.action_subdued?(check, handler).should be_true
    check[:subdue][:at] = 'publisher'
    @server.action_subdued?(check).should be_true
    check = {
      :subdue => {
        :begin => (Time.now + 3600).strftime('%l:00 %p').strip,
        :end => (Time.now + 7200).strftime('%l:00 %p').strip
      }
    }
    @server.action_subdued?(check, handler).should be_false
    check = {
      :subdue => {
        :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
        :end => (Time.now - 7200).strftime('%l:00 %p').strip
      }
    }
    @server.action_subdued?(check, handler).should be_true
    check = {
      :subdue => {
        :begin => (Time.now + 3600).strftime('%l:00 %p').strip,
        :end => (Time.now - 7200).strftime('%l:00 %p').strip
      }
    }
    @server.action_subdued?(check, handler).should be_false
    check = {
      :subdue => {
        :days => [
          Time.now.strftime('%A'),
          'wednesday'
        ]
      }
    }
    @server.action_subdued?(check, handler).should be_true
    check = {
      :subdue => {
        :days => [
          (Time.now + 86400).strftime('%A'),
          (Time.now + 172800).strftime('%A')
        ]
      }
    }
    @server.action_subdued?(check, handler).should be_false
    check = {
      :subdue => {
        :days => %w[sunday monday tuesday wednesday thursday friday saturday],
        :exceptions => [
          {
            :begin => (Time.now + 3600).rfc2822,
            :end => (Time.now + 7200)
          }
        ]
      }
    }
    @server.action_subdued?(check, handler).should be_true
    check = {
      :subdue => {
        :days => %w[sunday monday tuesday wednesday thursday friday saturday],
        :exceptions => [
          {
            :begin => (Time.now - 3600).rfc2822,
            :end => (Time.now + 3600).rfc2822
          }
        ]
      }
    }
    @server.action_subdued?(check, handler).should be_false
    check = Hash.new
    handler = {
      :subdue => {
        :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
        :end => (Time.now + 3600).strftime('%l:00 %p').strip
      }
    }
    @server.action_subdued?(check, handler).should be_true
    check = {
      :subdue => {
        :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
        :end => (Time.now + 3600).strftime('%l:00 %p').strip
      }
    }
    @server.action_subdued?(check, handler).should be_true
    check = {
      :subdue => {
        :begin => (Time.now + 3600).strftime('%l:00 %p').strip,
        :end => (Time.now + 7200).strftime('%l:00 %p').strip
      }
    }
    @server.action_subdued?(check, handler).should be_true
    handler = {
      :subdue => {
        :begin => (Time.now + 3600).strftime('%l:00 %p').strip,
        :end => (Time.now + 7200).strftime('%l:00 %p').strip
      }
    }
    @server.action_subdued?(check, handler).should be_false
  end

  it 'can determine if filter attributes match an event' do
    attributes = {
      :occurrences => 1
    }
    event = event_template
    @server.filter_attributes_match?(attributes, event).should be_true
    event[:occurrences] = 2
    @server.filter_attributes_match?(attributes, event).should be_false
    attributes[:occurrences] = "eval: value == 1 || value % 60 == 0"
    event[:occurrences] = 1
    @server.filter_attributes_match?(attributes, event).should be_true
    event[:occurrences] = 2
    @server.filter_attributes_match?(attributes, event).should be_false
    event[:occurrences] = 120
    @server.filter_attributes_match?(attributes, event).should be_true
  end

  it 'can determine if a event is to be filtered' do
    event = event_template
    event[:client][:environment] = 'production'
    @server.event_filtered?('production', event).should be_false
    @server.event_filtered?('development', event).should be_true
  end

  it 'can derive handlers from a handler list' do
    handler_list = ['default', 'file', 'missing']
    handlers = @server.derive_handlers(handler_list)
    handlers.first.should be_an_instance_of(Sensu::Extension::Debug)
    expected = {
      :name => 'file',
      :type => 'pipe',
      :command => 'cat > /tmp/sensu_event'
    }
    handlers.last.should eq(expected)
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
    @server.event_handlers(event).should eq(expected)
    event[:client][:environment] = 'development'
    expected << {
      :name => 'filtered',
      :type => 'pipe',
      :command => 'cat > /tmp/sensu_event',
      :filter => 'development'
    }
    @server.event_handlers(event).should eq(expected)
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
    @server.event_handlers(event).should eq(expected)
    event[:check][:status] = 0
    event[:action] = :resolve
    @server.event_handlers(event).should eq(expected)
    event[:action] = :flapping
    @server.event_handlers(event).should be_empty
    event[:check].delete(:handlers)
    event[:check][:handler] = 'flapping'
    expected = [
      {
        :name => 'flapping',
        :type => 'pipe',
        :command => 'cat > /tmp/sensu_event',
        :handle_flapping => true
      }
    ]
    @server.event_handlers(event).should eq(expected)
  end

  it 'can execute a command asynchronously' do
    timestamp = epoch.to_s
    file_name = File.join('/tmp', timestamp)
    on_error = Proc.new do
      raise 'failed to execute command'
    end
    async_wrapper do
      @server.execute_command('cat > ' + file_name, timestamp, on_error) do
        async_done
      end
    end
    File.exists?(file_name).should be_true
    File.open(file_name, 'r').read.should eq(timestamp)
    File.delete(file_name)
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
        event_data.should eq(Oj.dump(event))
        @server.mutate_event_data('only_check_output', event) do |event_data|
          event_data.should eq('WARNING')
          @server.mutate_event_data('tag', event) do |event_data|
            Oj.load(event_data).should include(:mutated)
            @server.mutate_event_data('settings', event) do |event_data|
              event_data.should eq('true')
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
    File.exists?('/tmp/sensu_event').should be_true
    File.delete('/tmp/sensu_event')
  end

  it 'can handle an event with a tcp handler' do
    async_wrapper do
      event = event_template
      event[:check][:handler] = 'tcp'
      EM::start_server('127.0.0.1', 1234, Helpers::TestServer) do |server|
        server.expected = Oj.dump(event)
      end
      @server.handle_event(event)
    end
  end

  it 'can handle an event with a udp handler' do
    async_wrapper do
      event = event_template
      event[:check][:handler] = 'udp'
      EM::open_datagram_socket('127.0.0.1', 1234, Helpers::TestServer) do |server|
        server.expected = Oj.dump(event)
      end
      @server.handle_event(event)
    end
  end

  it 'can handle an event with a amqp handler' do
    async_wrapper do
      @server.setup_rabbitmq
      event = event_template
      event[:check][:handler] = 'amqp'
      amq.direct('events') do
        queue = amq.queue('', :auto_delete => true).bind('events') do
          @server.handle_event(event)
        end
        queue.subscribe do |payload|
          payload.should eq(Oj.dump(event))
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
          result_set = 'foobar:' + timestamp.to_s
          redis.sismember('aggregates', 'foobar') do |exists|
            exists.should be_true
            redis.sismember('aggregates:foobar', timestamp.to_s) do |exists|
              exists.should be_true
              redis.hgetall('aggregate:' + result_set) do |aggregate|
                aggregate['total'].should eq('4')
                aggregate['ok'].should eq('1')
                aggregate['warning'].should eq('1')
                aggregate['critical'].should eq('1')
                aggregate['unknown'].should eq('1')
                redis.hgetall('aggregation:' + result_set) do |aggregation|
                  clients.each do |client_name|
                    aggregation.should include(client_name)
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
        redis.set('client:i-424242', Oj.dump(client)) do
          26.times do |index|
            result = result_template
            result[:check][:low_flap_threshold] = 5
            result[:check][:high_flap_threshold] = 20
            result[:check][:status] = index % 2
            @server.process_result(result)
          end
          timer(1) do
            redis.llen('history:i-424242:foobar') do |length|
              length.should eq(21)
              redis.hget('events:i-424242', 'foobar') do |event_json|
                event = Oj.load(event_json)
                event[:flapping].should be_true
                event[:occurrences].should be_within(2).of(1)
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
      @server.setup_rabbitmq
      @server.setup_redis
      @server.setup_results
      redis.flushdb do
        client = client_template
        redis.set('client:i-424242', Oj.dump(client)) do
          result = result_template
          amq.direct('results').publish(Oj.dump(result))
          timer(1) do
            redis.hget('events:i-424242', 'foobar') do |event_json|
              event = Oj.load(event_json)
              event[:status].should eq(1)
              event[:occurrences].should eq(1)
              async_done
            end
          end
        end
      end
    end
  end

  it 'can publish check requests' do
    async_wrapper do
      @server.setup_rabbitmq
      amq.fanout('test') do
        check = check_template
        check[:subscribers] = ['test']
        queue = amq.queue('', :auto_delete => true).bind('test') do
          @server.publish_check_request(check)
        end
        queue.subscribe do |payload|
          check_request = Oj.load(payload)
          check_request[:name].should eq('foobar')
          check_request[:command].should eq('echo -n WARNING && exit 1')
          check_request[:issued].should be_within(10).of(epoch)
          async_done
        end
      end
    end
  end

  it 'can schedule check request publishing' do
    async_wrapper do
      @server.setup_rabbitmq
      @server.setup_publisher
      amq.fanout('test') do
        expected = ['tokens', 'merger', 'sensu_cpu_time']
        amq.queue('', :auto_delete => true).bind('test').subscribe do |payload|
          check_request = Oj.load(payload)
          check_request[:issued].should be_within(10).of(epoch)
          expected.delete(check_request[:name]).should_not be_nil
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
        @server.setup_rabbitmq
        client = client_template
        check = result_template[:check]
        @server.publish_result(client, check)
        queue.subscribe do |payload|
          result = Oj.load(payload)
          result[:client].should eq('i-424242')
          result[:check][:name].should eq('foobar')
          async_done
        end
      end
    end
  end

  it 'can determine stale clients and create the appropriate events' do
    async_wrapper do
      @server.setup_redis
      @server.setup_rabbitmq
      @server.setup_results
      client1 = client_template
      client1[:name] = 'foo'
      client1[:timestamp] = epoch - 60
      client1[:keepalive][:handler] = 'debug'
      client2 = client_template
      client2[:name] = 'bar'
      client2[:timestamp] = epoch - 120
      redis.set('client:foo', Oj.dump(client1)) do
        redis.sadd('clients', 'foo') do
          redis.set('client:bar', Oj.dump(client2)) do
            redis.sadd('clients', 'bar') do
              @server.determine_stale_clients
              timer(1) do
                redis.hget('events:foo', 'keepalive') do |event_json|
                  event = Oj.load(event_json)
                  event[:status].should eq(1)
                  event[:handlers].should eq(['debug'])
                  redis.hget('events:bar', 'keepalive') do |event_json|
                    event = Oj.load(event_json)
                    event[:status].should eq(2)
                    event[:handlers].should eq(['default'])
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
        redis.set('client:i-424242', Oj.dump(client)) do
          timestamp = epoch - 26
          26.times do |index|
            result = result_template
            result[:check][:issued] = timestamp + index
            result[:check][:status] = index
            @server.aggregate_result(result)
          end
          timer(1) do
            redis.smembers('aggregates:foobar') do |aggregates|
              aggregates.sort!
              aggregates.size.should eq(26)
              oldest = aggregates.shift
              @server.prune_aggregations
              timer(1) do
                redis.smembers('aggregates:foobar') do |aggregates|
                  aggregates.size.should eq(20)
                  aggregates.should_not include(oldest)
                  result_set = 'foobar:' + oldest
                  redis.exists('aggregate:' + result_set) do |exists|
                    exists.should be_false
                    redis.exists('aggregation:' + result_set) do |exists|
                      exists.should be_false
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
      @server.setup_rabbitmq
      redis.flushdb do
        @server.request_master_election
        timer(1) do
          @server.is_master.should be_true
          @server.resign_as_master do
            @server.is_master.should be_false
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
      server1.setup_rabbitmq
      server2.setup_rabbitmq
      redis.flushdb do
        redis.set('lock:master', epoch - 60) do
          server1.setup_master_monitor
          server2.setup_master_monitor
          timer(1) do
            [server1.is_master, server2.is_master].uniq.size.should eq(2)
            async_done
          end
        end
      end
    end
  end

  after(:all) do
    async_wrapper do
      amq.queue('results').purge do
        amq.queue('keepalives').purge do
          async_done
        end
      end
    end
  end
end
