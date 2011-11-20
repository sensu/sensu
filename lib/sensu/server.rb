require File.join(File.dirname(__FILE__), 'config')

require 'redis'

module Sensu
  class Server
    attr_accessor :redis, :is_worker

    def self.run(options={})
      EM.threadpool_size = 16
      EM.run do
        server = self.new(options)
        server.setup_redis
        server.setup_amqp
        server.setup_keepalives
        server.setup_results
        unless server.is_worker
          server.setup_publisher
          server.setup_keepalive_monitor
        end
        server.setup_queue_monitor

        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            server.stop(signal)
          end
        end
      end
    end

    def initialize(options={})
      config = Sensu::Config.new(options)
      @settings = config.settings
      @logger = config.logger
      @is_worker = options[:worker]
    end

    def stop(signal)
      @logger.warn('[process] -- ' + signal + ' -- stopping sensu server')
      EM.add_timer(1) do
        EM.stop
      end
    end

    def setup_redis
      @logger.debug('[redis] -- connecting to redis')
      @redis = EM.connect(@settings.redis.host, @settings.redis.port, Redis::Client)
    end

    def setup_amqp
      @logger.debug('[amqp] -- connecting to rabbitmq')
      connection = AMQP.connect(@settings.rabbitmq.to_hash.symbolize_keys)
      @amq = MQ.new(connection)
    end

    def setup_keepalives
      @logger.debug('[keepalive] -- setup keepalive')
      @keepalive_queue = @amq.queue('keepalives')
      @keepalive_queue.subscribe do |keepalive_json|
        client = Hashie::Mash.new(JSON.parse(keepalive_json))
        @logger.debug('[keepalive] -- received keepalive -- ' + client.name)
        @redis.set('client:' + client.name, keepalive_json).callback do
          @redis.sadd('clients', client.name)
        end
      end
    end

    def handle_event(event)
      handler = proc do
        output = ''
        Bundler.with_clean_env do
          IO.popen(@settings.handlers[event.check.handler] + ' 2>&1', 'r+') do |io|
            io.write(event.to_json)
            io.close_write
            output = io.read
          end
        end
        output
      end
      report = proc do |output|
        output.split(/\n+/).each do |line|
          @logger.info('[handler] -- ' + line)
        end
      end
      if @settings.handlers.key?(event.check.handler)
        @logger.debug('[event] -- handling event -- ' + [event.check.handler, event.client.name, event.check.name].join(' -- '))
        EM.defer(handler, report)
      else
        @logger.warn('[event] -- handler does not exist -- ' + event.check.handler)
      end
    end

    def process_result(result)
      @logger.debug('[result] -- processing result for ' + [result.client, result.check.name].join(' -- '))
      @redis.get('client:' + result.client).callback do |client_json|
        unless client_json.nil?
          client = Hashie::Mash.new(JSON.parse(client_json))
          check = @settings.checks.key?(result.check.name) ? result.check.merge(@settings.checks[result.check.name]) : result.check
          check.handler ||= 'default'
          event = Hashie::Mash.new({
            :client => client,
            :check => check,
            :occurrences => 1
          })
          if check.type == 'metric'
            handle_event(event)
          else
            history_key = 'history:' + client.name + ':' + check.name
            @redis.rpush(history_key, check.status).callback do
              @redis.lrange(history_key, -21, -1).callback do |history|
                total_state_change = 0
                unless history.count < 21
                  state_changes = 0
                  change_weight = 0.8
                  history.each do |status|
                    previous_status ||= status
                    unless status == previous_status
                      state_changes += change_weight
                    end
                    change_weight += 0.02
                    previous_status = status
                  end
                  total_state_change = (state_changes.fdiv(20) * 100).to_i
                  @redis.lpop(history_key)
                end
                high_flap_threshold = check.high_flap_threshold || 50
                low_flap_threshold = check.low_flap_threshold || 40
                @redis.hget('events:' + client.name, check.name).callback do |event_json|
                  previous_event = event_json ? Hashie::Mash.new(JSON.parse(event_json)) : false
                  is_flapping = previous_event ? previous_event.flapping : false
                  is_flapping = case
                  when total_state_change >= high_flap_threshold
                    true
                  when is_flapping && total_state_change <= low_flap_threshold
                    false
                  else
                    is_flapping
                  end
                  if previous_event && check.status == 0
                    unless is_flapping
                      @redis.hdel('events:' + client.name, check.name).callback do
                        unless check.internal
                          event.action = 'resolve'
                          handle_event(event)
                        end
                      end
                    else
                      @logger.debug('[result] -- check is flapping -- ' + client.name + ' -- ' + check.name)
                      @redis.hset('events:' + client.name, check.name, previous_event.merge({'flapping' => true}).to_json)
                    end
                  elsif check['status'] != 0
                    if previous_event && check.status == previous_event.status
                      event.occurrences = previous_event.occurrences += 1
                    end
                    @redis.hset('events:' + client.name, check.name, {
                      :status => check.status,
                      :output => check.output,
                      :flapping => is_flapping,
                      :occurrences => event.occurrences
                    }.to_json).callback do
                      unless check.internal
                        event.check.flapping = is_flapping
                        event.action = 'create'
                        handle_event(event)
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

    def setup_results
      @logger.debug('[result] -- setup results')
      @result_queue = @amq.queue('results')
      @result_queue.subscribe do |result_json|
        result = Hashie::Mash.new(JSON.parse(result_json))
        @logger.info('[result] -- received result -- ' + result.client + ' -- ' + result.check.name)
        process_result(result)
      end
    end

    def setup_publisher(options={})
      @logger.debug('[publisher] -- setup publisher')
      exchanges = Hash.new
      stagger = options[:test] ? 0 : 7
      @settings.checks.each_with_index do |(name, details), index|
        check = Hashie::Mash.new
        check.name = name
        unless details.enabled == false
          EM.add_timer(stagger*index) do
            details.subscribers.each do |subscriber|
              if subscriber.is_a?(Hash)
                check.matching = subscriber
                exchange = 'uchiwa'
              else
                exchange = subscriber
              end
              exchanges[exchange] ||= @amq.fanout(exchange)
              interval = options[:test] ? 0.5 : details.interval
              EM.add_periodic_timer(interval) do
                check.issued = Time.now.to_i
                @logger.info('[publisher] -- publishing check -- ' + name + ' -- ' + exchange)
                exchanges[exchange].publish(check.to_json)
              end
            end
          end
        end
      end
    end

    def setup_keepalive_monitor
      @logger.debug('[keepalive] -- setup keepalive monitor')
      EM.add_periodic_timer(30) do
        @logger.debug('[keepalive] -- checking for stale clients')
        @redis.smembers('clients').callback do |clients|
          clients.each do |client_id|
            @redis.get('client:' + client_id).callback do |client_json|
              client = Hashie::Mash.new(JSON.parse(client_json))
              time_since_last_check = Time.now.to_i - client.timestamp
              result = Hashie::Mash.new({
                :client => client.name,
                :check => {
                  :name => 'keepalive',
                  :issued => Time.now.to_i
                }
              })
              case
              when time_since_last_check >= 180
                result.check.status = 2
                result.check.output = 'No keep-alive sent from host in over 180 seconds'
                @result_queue.publish(result.to_json)
              when time_since_last_check >= 120
                result.check.status = 1
                result.check.output = 'No keep-alive sent from host in over 120 seconds'
                @result_queue.publish(result.to_json)
              else
                @redis.hexists('events:' + client_id, 'keepalive').callback do |exists|
                  if exists
                    result.check.status = 0
                    result.check.output = 'Keep-alive sent from host'
                    @result_queue.publish(result.to_json)
                  end
                end
              end
            end
          end
        end
      end
    end

    def setup_queue_monitor
      @logger.debug('[monitor] -- setup queue monitor')
      EM.add_periodic_timer(5) do
        unless @keepalive_queue.subscribed?
          @logger.warn('[monitor] -- reconnecting to rabbitmq')
          setup_keepalives
        end
        unless @result_queue.subscribed?
          @logger.warn('[monitor] -- reconnecting to rabbitmq')
          setup_results
        end
      end
    end
  end
end
