require File.join(File.dirname(__FILE__), 'base')
require File.join(File.dirname(__FILE__), 'redis')

module Sensu
  class Server
    attr_reader :redis, :amq, :is_master

    def self.run(options={})
      server = self.new(options)
      EM::run do
        server.start
        server.trap_signals
      end
    end

    def initialize(options={})
      @logger = Sensu::Logger.get
      base = Sensu::Base.new(options)
      @settings = base.settings
      @timers = Array.new
      @master_timers = Array.new
      @handlers_in_progress_count = 0
      @is_master = false
    end

    def setup_redis
      @logger.debug('connecting to redis', {
        :settings => @settings[:redis]
      })
      connection_failure = Proc.new do
        @logger.fatal('cannot connect to redis', {
          :settings => @settings[:redis]
        })
        @logger.fatal('SENSU NOT RUNNING!')
        if @rabbitmq
          @rabbitmq.close
        end
        exit 2
      end
      @redis = Sensu::Redis.connect(@settings[:redis], :on_tcp_connection_failure => connection_failure)
      @redis.on_tcp_connection_loss do
        unless testing?
          @logger.fatal('redis connection closed')
          stop
        end
      end
    end

    def setup_rabbitmq
      @logger.debug('connecting to rabbitmq', {
        :settings => @settings[:rabbitmq]
      })
      connection_failure = Proc.new do
        @logger.fatal('cannot connect to rabbitmq', {
          :settings => @settings[:rabbitmq]
        })
        @logger.fatal('SENSU NOT RUNNING!')
        @redis.close
        exit 2
      end
      @rabbitmq = AMQP.connect(@settings[:rabbitmq], :on_tcp_connection_failure => connection_failure)
      @rabbitmq.logger = Sensu::NullLogger.get
      @rabbitmq.on_tcp_connection_loss do |connection, settings|
        @logger.warn('reconnecting to rabbitmq')
        resign_as_master do
          connection.reconnect(false, 10)
        end
      end
      @rabbitmq.on_skipped_heartbeats do
        @logger.warn('skipped rabbitmq heartbeat')
      end
      @amq = AMQP::Channel.new(@rabbitmq)
      @amq.auto_recovery = true
    end

    def store_client(client)
      @logger.debug('storing client', {
        :client => client
      })
      @redis.set('client:' + client[:name], client.to_json).callback do
        @redis.sadd('clients', client[:name])
      end
    end

    def setup_keepalives
      @logger.debug('subscribing to keepalives')
      @keepalive_queue = @amq.queue('keepalives')
      @keepalive_queue.subscribe do |payload|
        client = JSON.parse(payload, :symbolize_names => true)
        @logger.debug('received keepalive', {
          :client => client
        })
        store_client(client)
      end
    end

    def check_subdued?(check, subdue_at)
      subdue = false
      if check[:subdue].is_a?(Hash)
        if check[:subdue].has_key?(:begin) && check[:subdue].has_key?(:end)
          begin_time = Time.parse(check[:subdue][:begin])
          end_time = Time.parse(check[:subdue][:end])
          if end_time < begin_time
            if Time.now < end_time
              begin_time = Time.parse('12:00:00 AM')
            else
              end_time = Time.parse('11:59:59 PM')
            end
          end
          if Time.now >= begin_time && Time.now <= end_time
            subdue = true
          end
        end
        if check[:subdue].has_key?(:days)
          days = check[:subdue][:days].map(&:downcase)
          if days.include?(Time.now.strftime('%A').downcase)
            subdue = true
          end
        end
        if subdue && check[:subdue].has_key?(:exceptions)
          subdue = check[:subdue][:exceptions].none? do |exception|
            Time.now >= Time.parse(exception[:begin]) && Time.now <= Time.parse(exception[:end])
          end
        end
      end
      subdue && subdue_at == (check[:subdue][:at] || 'handler').to_sym
    end

    def check_handlers(check)
      handler_list = case
      when check.has_key?(:handler)
        [check[:handler]]
      when check.has_key?(:handlers)
        check[:handlers]
      else
        ['default']
      end
      handler_list.map! do |handler_name|
        if @settings.handler_exists?(handler_name) && @settings[:handlers][handler_name][:type] == 'set'
          @settings[:handlers][handler_name][:handlers]
        else
          handler_name
        end
      end
      handler_list.flatten!
      handler_list.uniq!
      handler_list.reject! do |handler_name|
        unless @settings.handler_exists?(handler_name)
          @logger.warn('unknown handler', {
            :handler => {
              :name => handler_name
            }
          })
          true
        else
          false
        end
      end
      handler_list.map do |handler_name|
        @settings[:handlers][handler_name].merge(:name => handler_name)
      end
    end

    def mutate_event_data(handler, event)
      if handler.has_key?(:mutator)
        mutated = nil
        case handler[:mutator]
        when /^only_check_output/
          if handler[:type] == 'amqp' && handler[:mutator] =~ /split$/
            mutated = Array.new
            event[:check][:output].split(/\n+/).each do |line|
              mutated.push(line)
            end
          else
            mutated = event[:check][:output]
          end
        else
          if @settings.mutator_exists?(handler[:mutator])
            mutator = @settings[:mutators][handler[:mutator]]
            begin
              IO.popen(mutator[:command], 'r+') do |io|
                io.write(event.to_json)
                io.close_write
                mutated = io.read
              end
              if $?.exitstatus != 0
                @logger.warn('mutator had a non-zero exit status', {
                  :event => event,
                  :mutator => mutator
                })
              end
            rescue => error
              @logger.error('mutator error', {
                :event => event,
                :mutator => mutator,
                :error => error.to_s
              })
            end
          else
            @logger.warn('unknown mutator', {
              :mutator => {
                :name => handler[:mutator]
              }
            })
          end
        end
        mutated
      else
        event.to_json
      end
    end

    def handle_event(event)
      unless check_subdued?(event[:check], :handler)
        handlers = check_handlers(event[:check])
        handlers.each do |handler|
          log_level = event[:check][:type] == 'metric' ? :debug : :info
          @logger.send(log_level, 'handling event', {
            :event => event,
            :handler => handler
          })
          @handlers_in_progress_count += 1
          case handler[:type]
          when 'pipe'
            execute = Proc.new do
              begin
                mutated_event_data = mutate_event_data(handler, event)
                unless mutated_event_data.nil? || mutated_event_data.empty?
                  IO.popen(handler[:command] + ' 2>&1', 'r+') do |io|
                    io.write(mutated_event_data)
                    io.close_write
                    io.read.split(/\n+/).each do |line|
                      @logger.info(line)
                    end
                  end
                end
              rescue => error
                @logger.error('handler error', {
                  :event => event,
                  :handler => handler,
                  :error => error.to_s
                })
              end
            end
            complete = Proc.new do
              @handlers_in_progress_count -= 1
            end
            EM::defer(execute, complete)
          when 'tcp', 'udp'
            data = Proc.new do
              mutate_event_data(handler, event)
            end
            write = Proc.new do |data|
              begin
                case handler[:type]
                when 'tcp'
                  EM::connect(handler[:socket][:host], handler[:socket][:port], nil) do |socket|
                    socket.send_data(data)
                    socket.close_connection_after_writing
                  end
                when 'udp'
                  EM::open_datagram_socket('127.0.0.1', 0, nil) do |socket|
                    socket.send_datagram(data, handler[:socket][:host], handler[:socket][:port])
                    socket.close_connection_after_writing
                  end
                end
              rescue => error
                @logger.error('handler error', {
                  :event => event,
                  :handler => handler,
                  :error => error.to_s
                })
              end
              @handlers_in_progress_count -= 1
            end
            EM::defer(data, write)
          when 'amqp'
            exchange_name = handler[:exchange][:name]
            exchange_type = handler[:exchange].has_key?(:type) ? handler[:exchange][:type].to_sym : :direct
            exchange_options = handler[:exchange].reject do |key, value|
              [:name, :type].include?(key)
            end
            payloads = Proc.new do
              Array(mutate_event_data(handler, event))
            end
            publish = Proc.new do |payloads|
              payloads.each do |payload|
                unless payload.empty?
                  @amq.method(exchange_type).call(exchange_name, exchange_options).publish(payload)
                end
              end
              @handlers_in_progress_count -= 1
            end
            EM::defer(payloads, publish)
          when 'set'
            @logger.error('handler sets cannot be nested', {
              :handler => handler
            })
            @handlers_in_progress_count -= 1
          end
        end
      end
    end

    def store_result(result)
      @logger.debug('storing result', {
        :result => result
      })
      check = result[:check]
      result_set = check[:name] + ':' + check[:issued].to_s
      @redis.hset('aggregation:' + result_set, result[:client], {
        :output => check[:output],
        :status => check[:status]
      }.to_json).callback do
        statuses = %w[OK WARNING CRITICAL UNKNOWN]
        statuses.each do |status|
          @redis.hsetnx('aggregate:' + result_set, status, 0)
        end
        status = (statuses[check[:status]] || 'UNKNOWN')
        @redis.hincrby('aggregate:' + result_set, status, 1).callback do
          @redis.hincrby('aggregate:' + result_set, 'TOTAL', 1).callback do
            @redis.sadd('aggregates:' + check[:name], check[:issued]).callback do
              @redis.sadd('aggregates', check[:name])
            end
          end
        end
      end
    end

    def process_result(result)
      @logger.debug('processing result', {
        :result => result
      })
      @redis.get('client:' + result[:client]).callback do |client_json|
        unless client_json.nil?
          client = JSON.parse(client_json, :symbolize_names => true)
          check = case
          when @settings.check_exists?(result[:check][:name])
            @settings[:checks][result[:check][:name]].merge(result[:check])
          else
            result[:check]
          end
          if check[:aggregate]
            store_result(result)
          end
          event = {
            :client => client,
            :check => check,
            :occurrences => 1
          }
          @redis.sadd('history:' + client[:name], check[:name])
          history_key = 'history:' + client[:name] + ':' + check[:name]
          @redis.rpush(history_key, check[:status]).callback do
            @redis.lrange(history_key, -21, -1).callback do |history|
              event[:check][:history] = history
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
              @redis.hget('events:' + client[:name], check[:name]).callback do |event_json|
                previous_occurrence = event_json ? JSON.parse(event_json, :symbolize_names => true) : false
                is_flapping = false
                if check.has_key?(:low_flap_threshold) && check.has_key?(:high_flap_threshold)
                  was_flapping = previous_occurrence ? previous_occurrence[:flapping] : false
                  is_flapping = case
                  when total_state_change >= check[:high_flap_threshold]
                    true
                  when was_flapping && total_state_change <= check[:low_flap_threshold]
                    false
                  else
                    was_flapping
                  end
                end
                if check[:status] != 0
                  if previous_occurrence && check[:status] == previous_occurrence[:status]
                    event[:occurrences] = previous_occurrence[:occurrences] += 1
                  end
                  @redis.hset('events:' + client[:name], check[:name], {
                    :output => check[:output],
                    :status => check[:status],
                    :issued => check[:issued],
                    :flapping => is_flapping,
                    :occurrences => event[:occurrences]
                  }.to_json).callback do
                    unless check[:handle] == false
                      event[:check][:flapping] = is_flapping
                      event[:action] = 'create'
                      handle_event(event)
                    else
                      @logger.debug('handling disabled', {
                        :event => event
                      })
                    end
                  end
                elsif previous_occurrence
                  unless is_flapping
                    unless check[:auto_resolve] == false && !check[:force_resolve]
                      @redis.hdel('events:' + client[:name], check[:name]).callback do
                        unless check[:handle] == false
                          event[:occurrences] = previous_occurrence[:occurrences]
                          event[:action] = 'resolve'
                          handle_event(event)
                        else
                          @logger.debug('handling disabled', {
                            :event => event
                          })
                        end
                      end
                    end
                  else
                    @logger.debug('check is flapping', {
                      :event => event
                    })
                    @redis.hset('events:' + client[:name], check[:name], previous_occurrence.merge(:flapping => true).to_json).callback do
                      if check[:type] == 'metric'
                        event[:check][:flapping] = is_flapping
                        handle_event(event)
                      end
                    end
                  end
                elsif check[:type] == 'metric'
                  handle_event(event)
                end
              end
            end
          end
        end
      end
    end

    def setup_results
      @logger.debug('subscribing to results')
      @result_queue = @amq.queue('results')
      @result_queue.subscribe do |payload|
        result = JSON.parse(payload, :symbolize_names => true)
        @logger.debug('received result', {
          :result => result
        })
        process_result(result)
      end
    end

    def publish_check_request(check)
      payload = {
        :name => check[:name],
        :command => check[:command],
        :issued => Time.now.to_i
      }
      @logger.info('publishing check request', {
        :payload => payload,
        :subscribers => check[:subscribers]
      })
      check[:subscribers].uniq.each do |exchange_name|
        @amq.fanout(exchange_name).publish(payload.to_json)
      end
    end

    def setup_publisher
      @logger.debug('scheduling check requests')
      check_count = 0
      stagger = testing? ? 0 : 7
      @settings.checks.each do |check|
        unless check[:publish] == false || check[:standalone]
          check_count += 1
          @master_timers << EM::Timer.new(stagger * check_count) do
            interval = testing? ? 0.5 : check[:interval]
            @master_timers << EM::PeriodicTimer.new(interval) do
              unless check_subdued?(check, :publisher)
                publish_check_request(check)
              end
            end
          end
        end
      end
    end

    def publish_result(client, check)
      payload = {
        :client => client[:name],
        :check => check
      }
      @logger.info('publishing check result', {
        :payload => payload
      })
      @amq.queue('results').publish(payload.to_json)
    end

    def setup_keepalive_monitor
      @logger.debug('monitoring client keepalives')
      @master_timers << EM::PeriodicTimer.new(30) do
        @redis.smembers('clients').callback do |clients|
          clients.each do |client_name|
            @redis.get('client:' + client_name).callback do |client_json|
              client = JSON.parse(client_json, :symbolize_names => true)
              check = {
                :name => 'keepalive',
                :issued => Time.now.to_i
              }
              time_since_last_keepalive = Time.now.to_i - client[:timestamp]
              case
              when time_since_last_keepalive >= 180
                check[:output] = 'No keep-alive sent from client in over 180 seconds'
                check[:status] = 2
                publish_result(client, check)
              when time_since_last_keepalive >= 120
                check[:output] = 'No keep-alive sent from client in over 120 seconds'
                check[:status] = 1
                publish_result(client, check)
              else
                @redis.hexists('events:' + client[:name], 'keepalive').callback do |exists|
                  if exists
                    check[:output] = 'Keep-alive sent from client'
                    check[:status] = 0
                    publish_result(client, check)
                  end
                end
              end
            end
          end
        end
      end
    end

    def setup_aggregation_pruner
      @logger.debug('pruning aggregations')
      @master_timers << EM::PeriodicTimer.new(20) do
        @redis.smembers('aggregates').callback do |checks|
          checks.each do |check_name|
            @redis.smembers('aggregates:' + check_name).callback do |aggregates|
              aggregates.sort!
              until aggregates.size <= 10
                check_issued = aggregates.shift
                @redis.srem('aggregates:' + check_name, check_issued).callback do
                  result_set = check_name + ':' + check_issued.to_s
                  @redis.del('aggregate:' + result_set).callback do
                    @redis.del('aggregation:' + result_set).callback do
                      @logger.debug('pruned aggregation', {
                        :check => {
                          :name => check_name,
                          :issued => check_issued
                        }
                      })
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
      setup_aggregation_pruner
    end

    def request_master_election
      @redis.setnx('lock:master', Time.now.to_i).callback do |created|
        if created
          @is_master = true
          @logger.info('i am the master')
          master_duties
        else
          @redis.get('lock:master').callback do |timestamp|
            if Time.now.to_i - timestamp.to_i >= 60
              @redis.getset('lock:master', Time.now.to_i).callback do |previous|
                if previous == timestamp
                  @is_master = true
                  @logger.info('i am now the master')
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
      @timers << EM::PeriodicTimer.new(20) do
        if @is_master
          @redis.set('lock:master', Time.now.to_i).callback do
            @logger.debug('updated master lock timestamp')
          end
        elsif @rabbitmq.connected?
          request_master_election
        end
      end
    end

    def resign_as_master(&block)
      if @is_master
        @logger.warn('resigning as master')
        @master_timers.each do |timer|
          timer.cancel
        end
        @master_timers = Array.new
        @redis.del('lock:master').callback do
          @logger.info('removed master lock')
          @is_master = false
        end
        timestamp = Time.now.to_i
        retry_until_true do
          if !@is_master
            block.call
            true
          elsif !@redis.connected? || Time.now.to_i - timestamp >= 5
            @logger.warn('failed to remove master lock')
            @is_master = false
            block.call
            true
          end
        end
      else
        @logger.debug('not currently master')
        block.call
      end
    end

    def unsubscribe(&block)
      @logger.warn('unsubscribing from keepalive and result queues')
      @keepalive_queue.unsubscribe
      @result_queue.unsubscribe
      if @rabbitmq.connected?
        timestamp = Time.now.to_i
        retry_until_true do
          if !@keepalive_queue.subscribed? && !@result_queue.subscribed?
            block.call
            true
          elsif Time.now.to_i - timestamp >= 5
            @logger.warn('failed to unsubscribe from keepalive and result queues')
            block.call
            true
          end
        end
      else
        block.call
      end
    end

    def complete_handlers_in_progress(&block)
      @logger.info('completing handlers in progress', {
        :handlers_in_progress_count => @handlers_in_progress_count
      })
      retry_until_true do
        if @handlers_in_progress_count == 0
          block.call
          true
        end
      end
    end

    def start
      setup_redis
      setup_rabbitmq
      setup_keepalives
      setup_results
      setup_master_monitor
    end

    def stop
      @logger.warn('stopping')
      @timers.each do |timer|
        timer.cancel
      end
      unsubscribe do
        resign_as_master do
          complete_handlers_in_progress do
            @rabbitmq.close
            @redis.close
            @logger.warn('stopping reactor')
            EM::stop_event_loop
          end
        end
      end
    end

    def trap_signals
      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          @logger.warn('received signal', {
            :signal => signal
          })
          stop
        end
      end
    end

    private

    def testing?
      File.basename($0) == 'rake'
    end

    def retry_until_true(wait=0.5, &block)
      EM::Timer.new(wait) do
        unless block.call
          retry_until_true(wait, &block)
        end
      end
    end
  end
end
