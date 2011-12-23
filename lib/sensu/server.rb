require File.join(File.dirname(__FILE__), 'config')

require 'redis'

require File.join(File.dirname(__FILE__), 'helpers', 'redis')

module Sensu
  class Server
    attr_accessor :redis, :amq, :is_master

    def self.run(options={})
      server = self.new(options)
      if options[:daemonize]
        Process.daemonize
      end
      if options[:pid_file]
        Process.write_pid(options[:pid_file])
      end
      EM.threadpool_size = 16
      EM.run do
        server.setup_redis
        server.setup_amqp
        server.setup_keepalives
        server.setup_results
        server.setup_master_monitor
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
      @logger = config.logger || config.open_log
      @status = nil
    end

    def stop_reactor
      EM.add_timer(3) do
        EM.stop
      end
    end

    def stopping?
      @status == :stopping
    end

    def setup_redis
      @logger.debug('[redis] -- connecting to redis')
      @redis = Redis.connect(@settings.redis.to_hash.symbolize_keys)
    end

    def setup_amqp
      @logger.debug('[amqp] -- connecting to rabbitmq')
      rabbitmq = AMQP.connect(@settings.rabbitmq.to_hash.symbolize_keys)
      @amq = AMQP::Channel.new(rabbitmq)
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
      handlers = case
      when event.check.key?('handler')
        [event.check.handler]
      when event.check.key?('handlers')
        event.check.handlers
      else
        ['default']
      end
      report = proc do |output|
        output.split(/\n+/).each do |line|
          @logger.info('[handler] -- ' + line)
        end
      end
      handlers.each do |handler|
        if @settings.handlers.key?(handler)
          @logger.debug('[event] -- handling event -- ' + [handler, event.client.name, event.check.name].join(' -- '))
          details = @settings.handlers[handler]
          case details.type
          when "pipe"
            handle = proc do
              output = ''
              Bundler.with_clean_env do
                begin
                  IO.popen(details.command + ' 2>&1', 'r+') do |io|
                    io.write(event.to_json)
                    io.close_write
                    output = io.read
                  end
                rescue Errno::EPIPE => error
                  output = handler + ' -- broken pipe: ' + error.to_s
                end
              end
              output
            end
            EM.defer(handle, report)
          when "amqp"
            exchange = details.exchange.name
            exchange_type = details.exchange.key?('type') ? details.exchange.type.to_sym : :direct
            exchange_options = details.exchange.reject { |key, value| %w[name type].include?(key) }
            @logger.debug('[event] -- publishing event to amqp exchange -- ' + [exchange, event.client.name, event.check.name].join(' -- '))
            payload = details.send_only_check_output ? event.check.output : event.to_json
            @amq.method(exchange_type).call(exchange, exchange_options).publish(payload)
          end
        else
          @logger.warn('[event] -- unknown handler -- ' + handler)
        end
      end
    end

    def process_result(result)
      @logger.debug('[result] -- processing result -- ' + result.client + ' -- ' + result.check.name)
      @redis.get('client:' + result.client).callback do |client_json|
        unless client_json.nil?
          client = Hashie::Mash.new(JSON.parse(client_json))
          check = @settings.checks.key?(result.check.name) ? result.check.merge(@settings.checks[result.check.name]) : result.check
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
                event.check.history = history
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
                @redis.hget('events:' + client.name, check.name).callback do |event_json|
                  previous_occurrence = event_json ? Hashie::Mash.new(JSON.parse(event_json)) : false
                  is_flapping = false
                  if check.key?('low_flap_threshold') && check.key?('high_flap_threshold')
                    was_flapping = previous_occurrence ? previous_occurrence.flapping : false
                    is_flapping = case
                    when total_state_change >= check.high_flap_threshold
                      true
                    when was_flapping && total_state_change <= check.low_flap_threshold
                      false
                    else
                      was_flapping
                    end
                  end
                  if previous_occurrence && check.status == 0
                    unless is_flapping
                      unless check.auto_resolve == false && !check.force_resolve
                        @redis.hdel('events:' + client.name, check.name).callback do
                          unless check.handle == false
                            event.action = 'resolve'
                            handle_event(event)
                          end
                        end
                      end
                    else
                      @logger.debug('[result] -- check is flapping -- ' + client.name + ' -- ' + check.name)
                      @redis.hset('events:' + client.name, check.name, previous_occurrence.merge({'flapping' => true}).to_json)
                    end
                  elsif check.status != 0
                    if previous_occurrence && check.status == previous_occurrence.status
                      event.occurrences = previous_occurrence.occurrences += 1
                    end
                    @redis.hset('events:' + client.name, check.name, {
                      :status => check.status,
                      :output => check.output,
                      :flapping => is_flapping,
                      :occurrences => event.occurrences
                    }.to_json).callback do
                      unless check.handle == false
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
        @logger.info('[result] -- received result -- ' + [result.check.name, result.client, result.check.status, result.check.output].join(' -- '))
        process_result(result)
      end
    end

    def setup_publisher(options={})
      @logger.debug('[publisher] -- setup publisher')
      stagger = options[:test] ? 0 : 7
      @settings.checks.each_with_index do |(name, details), index|
        check_request = Hashie::Mash.new({:name => name})
        unless details.publish == false
          EM.add_timer(stagger*index) do
            details.subscribers.each do |target|
              if target.is_a?(Hash)
                @logger.debug('[publisher] -- check requires matching -- ' + target.to_hash.to_s + ' -- ' + name)
                check_request.matching = target
                exchange = 'uchiwa'
              else
                exchange = target
              end
              interval = options[:test] ? 0.5 : details.interval
              EM.add_periodic_timer(interval) do
                unless stopping?
                  check_request.issued = Time.now.to_i
                  @logger.info('[publisher] -- publishing check -- ' + name + ' -- ' + exchange)
                  @amq.fanout(exchange).publish(check_request.to_json)
                end
              end
            end
          end
        end
      end
    end

    def setup_keepalive_monitor
      @logger.debug('[keepalive] -- setup keepalive monitor')
      EM.add_periodic_timer(30) do
        unless stopping?
          @logger.debug('[keepalive] -- checking for stale clients')
          @redis.smembers('clients').callback do |clients|
            clients.each do |client_id|
              @redis.get('client:' + client_id).callback do |client_json|
                client = Hashie::Mash.new(JSON.parse(client_json))
                time_since_last_keepalive = Time.now.to_i - client.timestamp
                result = Hashie::Mash.new({
                  :client => client.name,
                  :check => {
                    :name => 'keepalive',
                    :issued => Time.now.to_i
                  }
                })
                case
                when time_since_last_keepalive >= 180
                  result.check.status = 2
                  result.check.output = 'No keep-alive sent from host in over 180 seconds'
                  @amq.queue('results').publish(result.to_json)
                when time_since_last_keepalive >= 120
                  result.check.status = 1
                  result.check.output = 'No keep-alive sent from host in over 120 seconds'
                  @amq.queue('results').publish(result.to_json)
                else
                  @redis.hexists('events:' + client_id, 'keepalive').callback do |exists|
                    if exists
                      result.check.status = 0
                      result.check.output = 'Keep-alive sent from host'
                      @amq.queue('results').publish(result.to_json)
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    def master_duties
      setup_publisher
      setup_keepalive_monitor
    end

    def request_master_election
      @is_master ||= false
      @redis.setnx('lock:master', Time.now.to_i).callback do |created|
        if created
          @logger.info('[master] -- i am the master')
          @is_master = true
          master_duties
        else
          @redis.get('lock:master') do |timestamp|
            if Time.now.to_i - timestamp.to_i >= 60
              @redis.getset('lock:master', Time.now.to_i).callback do |previous|
                if previous == timestamp
                  @logger.info('[master] -- i am now the master')
                  @is_master = true
                  master_duties
                end
              end
            end
          end
        end
      end
    end

    def setup_master_monitor
      request_master_election
      EM.add_periodic_timer(20) do
        unless stopping?
          if @is_master
            timestamp = Time.now.to_i
            @redis.set('lock:master', timestamp).callback do
              @logger.debug('[master] -- updated master lock timestamp -- ' + timestamp.to_s)
            end
          else
            request_master_election
          end
        end
      end
    end

    def setup_queue_monitor
      @logger.debug('[monitor] -- setup queue monitor')
      EM.add_periodic_timer(5) do
        unless stopping?
          unless @keepalive_queue.subscribed?
            @logger.warn('[monitor] -- re-subscribing to rabbitmq queue -- keepalives')
            setup_keepalives
          end
          unless @result_queue.subscribed?
            @logger.warn('[monitor] -- re-subscribing to rabbitmq queue -- results')
            setup_results
          end
        end
      end
    end

    def stop(signal)
      @logger.warn('[stop] -- stopping sensu server -- ' + signal)
      @status = :stopping
      @keepalive_queue.unsubscribe do
        @logger.warn('[stop] -- unsubscribed from rabbitmq queue -- keepalives')
        @result_queue.unsubscribe do
          @logger.warn('[stop] -- unsubscribed from rabbitmq queue -- results')
          if @is_master
            @redis.del('lock:master').callback do
              @logger.warn('[stop] -- resigned as master')
              stop_reactor
            end
          else
            stop_reactor
          end
        end
      end
    end
  end
end
