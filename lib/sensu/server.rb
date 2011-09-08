require File.join(File.dirname(__FILE__), 'config')
require 'em-hiredis'

module Sensu
  class Server
    attr_accessor :redis

    def self.run(options={})
      EM.run do
        server = self.new(options)
        server.setup_logging
        server.setup_redis
        server.setup_amqp
        server.setup_keep_alives
        server.setup_handlers
        server.setup_results
        server.setup_publisher
        server.setup_populator
        server.setup_keep_alive_monitor

        Signal.trap('INT') do
          EM.stop
        end

        Signal.trap('TERM') do
          EM.stop
        end
      end
    end

    def initialize(options={})
      config = Sensu::Config.new(:config_file => options[:config_file])
      config.create_working_directory
      @settings = config.settings
    end

    def setup_logging
      EM.syslog_setup(@settings['syslog']['host'], @settings['syslog']['port'])
    end

    def setup_redis
      @redis = EM::Hiredis.connect('redis://' + @settings['redis']['host'] + ':' + @settings['redis']['port'].to_s)
    end

    def setup_amqp
      connection = AMQP.connect(symbolize_keys(@settings['rabbitmq']))
      @amq = AMQP::Channel.new(connection)
    end

    def setup_keep_alives
      @amq.queue('keepalives').subscribe do |keepalive_json|
        client = JSON.parse(keepalive_json)['name']
        @redis.set('client:' + client, keepalive_json).callback do
          @redis.sadd('clients', client)
        end
      end
    end

    def setup_handlers
      @handler_queue = EM::Queue.new
      handlers_in_progress = 0
      handle = Proc.new do |event|
        if handlers_in_progress < 15
          event_file = proc do
            handlers_in_progress += 1
            file_name = '/tmp/sensu/event-' + UUIDTools::UUID.random_create.to_s
            File.open(file_name, 'w') do |file|
              file.write(JSON.pretty_generate(event))
            end
            file_name
          end
          handler = proc do |event_file|
            EM.system('sh', '-c', @settings['handlers'][event['check']['handler']] + ' -f ' + event_file  + ' 2>&1') do |output, status|
              EM.debug('handled :: ' + event['check']['handler'] + ' :: ' + status.exitstatus.to_s + ' :: ' + output)
              File.delete(event_file)
              handlers_in_progress -= 1
            end
          end
          EM.defer(event_file, handler)
        else
          @handler_queue.push(event)
        end
        EM.next_tick do
          @handler_queue.pop(&handle)
        end
      end
      @handler_queue.pop(&handle)
    end

    def setup_results
      @amq.queue('results').subscribe do |result_json|
        result = JSON.parse(result_json)
        @redis.get('client:' + result['client']).callback do |client_json|
          unless client_json.nil?
            client = JSON.parse(client_json)
            check = {'name' => result['check']}
            check.merge!(@settings['checks'][result['check']]) if @settings['checks'].has_key?(result['check'])
            check['handler'] = 'default' unless check['handler']
            event = {
              'client' => client,
              'check' => check,
              'status' => result['status'],
              'output' => result['output']
            }
            if check['handler'] == 'metric'
              handle_event(event)
            else
              if result['status'] == 0
                @redis.hexists('events:' + client['name'], result['check']).callback do |exists|
                  if exists == 1
                    @redis.hdel('events:' + client['name'], result['check'])
                    event['action'] = 'resolve'
                    handle_event(event)
                  end
                end
              else
                @redis.hset('events:' + client['name'], result['check'], {'status' => result['status'], 'output' => result['output']}.to_json).callback do
                  event['action'] = 'create'
                  handle_event(event)
                end
              end
            end
          end
        end
      end
    end

    def handle_event(event)
      @handler_queue.push(event)
    end

    def setup_publisher
      exchanges = Hash.new
      @amq.queue('checks').subscribe do |check_json|
        check = JSON.parse(check_json)
        check['subscribers'].each do |exchange|
          if exchanges[exchange].nil?
            exchanges[exchange] = @amq.fanout(exchange)
          end
          exchanges[exchange].publish({'name' => check['name']}.to_json)
          EM.debug('published :: ' + exchange + ' :: ' + check['name'])
        end
      end
    end

    def setup_populator
      check_queue = @amq.queue('checks')
      @settings['checks'].each_with_index do |(name, info), index|
        EM.add_timer(7*index) do
          EM.add_periodic_timer(info['interval']) do
            check_queue.publish({'name' => name, 'subscribers' => info['subscribers']}.to_json)
          end
        end
      end
    end

    def setup_keep_alive_monitor
      result_queue = @amq.queue('results')
      EM.add_periodic_timer(30) do
        @redis.smembers('clients').callback do |clients|
          clients.each do |client_id|
            @redis.get('client:' + client_id).callback do |client_json|
              client = JSON.parse(client_json)
              time_since_last_check = Time.now.to_i - client['timestamp']
              case
              when time_since_last_check >= 180
                result_queue.publish({'check' => 'keepalive', 'client' => client['name'], 'status' => 2, 'output' => 'No keep-alive sent from host in over 180 seconds'}.to_json)
              when time_since_last_check >= 120
                result_queue.publish({'check' => 'keepalive', 'client' => client['name'], 'status' => 1, 'output' => 'No keep-alive sent from host in over 120 seconds'}.to_json)
              else
                @redis.hexists('events:' + client_id, 'keepalive').callback do |exists|
                  if exists == 1
                    result_queue.publish({'check' => 'keepalive', 'client' => client['name'], 'status' => 0, 'output' => 'Keep-alive sent from host'}.to_json)
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
