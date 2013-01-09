require File.dirname(__FILE__) + '/../lib/sensu/server.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe "Sensu::Server" do
  include Helpers

  before do
    @server = Sensu::Server.new(options)
  end

  it "can connect to redis" do
    async_wrapper do
      @server.setup_redis
      async_done
    end
  end

  it "can connect to rabbitmq" do
    async_wrapper do
      @server.setup_rabbitmq
      async_done
    end
  end

  it "can consume client keepalives" do
    async_wrapper do
      @server.setup_redis
      @server.setup_rabbitmq
      @server.setup_keepalives
      keepalive = {
        :name => 'foo',
        :address => '127.0.0.1',
        :subscriptions => [
          'bar'
        ],
        :timestamp => epoch
      }
      redis.flushdb do
        amq.queue('keepalives').publish(keepalive.to_json)
        timer(1) do
          redis.sismember('clients', 'foo') do |exists|
            exists.should be_true
            redis.get('client:foo') do |client_json|
              client = JSON.parse(client_json, :symbolize_names => true)
              client.should eq(keepalive)
              async_done
            end
          end
        end
      end
    end
  end

  it "can determine if a check is subdued" do
    @server.check_subdued?(Hash.new, :handler).should be_false
    check = {
      :subdue => {
        :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
        :end => (Time.now + 3600).strftime('%l:00 %p').strip
      }
    }
    @server.check_subdued?(check, :handler).should be_true
    @server.check_subdued?(check, :publisher).should be_false
    check[:subdue][:at] = :publisher
    @server.check_subdued?(check, :publisher).should be_true
    check = {
      :subdue => {
        :begin => (Time.now + 3600).strftime('%l:00 %p').strip,
        :end => (Time.now + 7200).strftime('%l:00 %p').strip
      }
    }
    @server.check_subdued?(check, :handler).should be_false
    check = {
      :subdue => {
        :begin => (Time.now - 3600).strftime('%l:00 %p').strip,
        :end => (Time.now - 7200).strftime('%l:00 %p').strip
      }
    }
    @server.check_subdued?(check, :handler).should be_true
    check = {
      :subdue => {
        :begin => (Time.now + 3600).strftime('%l:00 %p').strip,
        :end => (Time.now - 7200).strftime('%l:00 %p').strip
      }
    }
    @server.check_subdued?(check, :handler).should be_false
    check = {
      :subdue => {
        :days => [
          Time.now.strftime('%A'),
          'wednesday'
        ]
      }
    }
    @server.check_subdued?(check, :handler).should be_true
    check = {
      :subdue => {
        :days => [
          (Time.now + 86400).strftime('%A'),
          (Time.now + 172800).strftime('%A')
        ]
      }
    }
    @server.check_subdued?(check, :handler).should be_false
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
    @server.check_subdued?(check, :handler).should be_true
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
    @server.check_subdued?(check, :handler).should be_false
  end

  it "can determine if a event is to be filtered" do
    event = event_template
    event[:client][:environment] = 'production'
    @server.event_filtered?("production", event).should be_false
    @server.event_filtered?("development", event).should be_true
  end

  it "can derive handlers from a handler list" do
    handler_list = ["default", "file", "missing"]
    handlers = @server.derive_handlers(handler_list)
    handlers.first.should be_an_instance_of(Sensu::Extension::Debug)
    expected = {
      :name => 'file',
      :type => 'pipe',
      :command => 'cat > /tmp/sensu_event'
    }
    handlers.last.should eq(expected)
  end

  it "can determine handlers for an event" do
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
    expected.push({
      :name => 'filtered',
      :type => 'pipe',
      :command => 'cat > /tmp/sensu_event',
      :filter => 'development'
    })
    @server.event_handlers(event).should eq(expected)
    event[:check][:status] = 2
    expected.push({
      :name => 'severities',
      :type => 'pipe',
      :command => 'cat > /tmp/sensu_event',
      :severities => [
        'critical',
        'unknown'
      ]
    })
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

  it "can execute a command asynchronously" do
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

  it "can mutate event data" do
    async_wrapper do
      event = event_template
      @server.mutate_event_data(nil, event) do |event_data|
        event_data.should eq(event.to_json)
        @server.mutate_event_data('only_check_output', event) do |event_data|
          event_data.should eq('WARNING')
          @server.mutate_event_data('tag', event) do |event_data|
            expected = event.merge(:mutated => true).to_json
            event_data.chomp.should eq(expected)
            async_done
          end
        end
      end
    end
  end

  it "can handle an event with a pipe handler" do
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

  it "can handle an event with a tcp handler" do
    async_wrapper do
      event = event_template
      event[:check][:handler] = 'tcp'
      EM::start_server('127.0.0.1', 1234, Helpers::TestServer) do |server|
        server.expected = event.to_json
      end
      @server.handle_event(event)
    end
  end

  it "can handle an event with a udp handler" do
    async_wrapper do
      event = event_template
      event[:check][:handler] = 'udp'
      EM::open_datagram_socket('127.0.0.1', 1234, Helpers::TestServer) do |server|
        server.expected = event.to_json
      end
      @server.handle_event(event)
    end
  end

  it "can handle an event with a amqp handler" do
    async_wrapper do
      @server.setup_rabbitmq
      event = event_template
      event[:check][:handler] = 'amqp'
      amq.direct('events') do |exchange, declare_ok|
        binding = amq.queue('', :auto_delete => true).bind('events') do
          @server.handle_event(event)
        end
        binding.subscribe do |payload|
          payload.should eq(event.to_json)
          async_done
        end
      end
    end
  end

  it "can handle an event with an extension" do
    async_wrapper do
      event = event_template
      event[:check][:handler] = 'debug'
      @server.handle_event(event)
      timer(0.5) do
        async_done
      end
    end
  end
end
