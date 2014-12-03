require 'sensu/daemon'
require 'sensu/socket'
require 'sensu/sandbox'

module Sensu
  class Server
    include Daemon

    attr_reader :is_master

    def self.run(options={})
      server = self.new(options)
      EM::run do
        server.start
        server.setup_signal_traps
      end
    end

    def initialize(options={})
      super
      @is_master = false
      @timers[:master] = Array.new
      @handlers_in_progress_count = 0
    end

    def setup_keepalives
      @logger.debug('subscribing to keepalives')
      @transport.subscribe(:direct, 'keepalives', 'keepalives', :ack => true) do |message_info, message|
        begin
          client = MultiJson.load(message)
          @logger.debug('received keepalive', {
            :client => client
          })
          @redis.set('client:' + client[:name], MultiJson.dump(client)) do
            @redis.sadd('clients', client[:name]) do
              @transport.ack(message_info)
            end
          end
        rescue MultiJson::ParseError => error
          @logger.error('failed to parse keepalive payload', {
            :message => message,
            :error => error.to_s
          })
          @transport.ack(message_info)
        end
      end
    end

    def action_subdued?(condition)
      subdued = false
      if condition.has_key?(:begin) && condition.has_key?(:end)
        begin_time = Time.parse(condition[:begin])
        end_time = Time.parse(condition[:end])
        if end_time < begin_time
          if Time.now < end_time
            begin_time = Time.parse('12:00:00 AM')
          else
            end_time = Time.parse('11:59:59 PM')
          end
        end
        if Time.now >= begin_time && Time.now <= end_time
          subdued = true
        end
      end
      if condition.has_key?(:days)
        days = condition[:days].map(&:downcase)
        if days.include?(Time.now.strftime('%A').downcase)
          subdued = true
        end
      end
      if subdued && condition.has_key?(:exceptions)
        subdued = condition[:exceptions].none? do |exception|
          Time.now >= Time.parse(exception[:begin]) && Time.now <= Time.parse(exception[:end])
        end
      end
      subdued
    end

    def handler_subdued?(handler, check)
      subdued = Array.new
      if handler[:subdue]
        subdued << action_subdued?(handler[:subdue])
      end
      if check[:subdue] && check[:subdue][:at] != 'publisher'
        subdued << action_subdued?(check[:subdue])
      end
      subdued.any?
    end

    def filter_attributes_match?(hash_one, hash_two)
      hash_one.keys.all? do |key|
        case
        when hash_one[key] == hash_two[key]
          true
        when hash_one[key].is_a?(Hash) && hash_two[key].is_a?(Hash)
          filter_attributes_match?(hash_one[key], hash_two[key])
        when hash_one[key].is_a?(String) && hash_one[key].start_with?('eval:')
          begin
            expression = hash_one[key].gsub(/^eval:(\s+)?/, '')
            !!Sandbox.eval(expression, hash_two[key])
          rescue => error
            @logger.error('filter eval error', {
              :attributes => [hash_one, hash_two],
              :error => error.to_s
            })
            false
          end
        else
          false
        end
      end
    end

    def event_filtered?(filter_name, event)
      if @settings.filter_exists?(filter_name)
        filter = @settings[:filters][filter_name]
        matched = filter_attributes_match?(filter[:attributes], event)
        filter[:negate] ? matched : !matched
      else
        @logger.error('unknown filter', {
          :filter_name => filter_name
        })
        false
      end
    end

    def derive_handlers(handler_list, depth=0)
      handler_list.compact.inject(Array.new) do |handlers, handler_name|
        if @settings.handler_exists?(handler_name)
          handler = @settings[:handlers][handler_name].merge(:name => handler_name)
          if handler[:type] == 'set'
            if depth < 2
              handlers = handlers + derive_handlers(handler[:handlers], depth + 1)
            else
              @logger.error('handler sets cannot be deeply nested', {
                :handler => handler
              })
            end
          else
            handlers << handler
          end
        elsif @extensions.handler_exists?(handler_name)
          handlers << @extensions[:handlers][handler_name]
        else
          @logger.error('unknown handler', {
            :handler_name => handler_name
          })
        end
        handlers.uniq
      end
    end

    def event_handlers(event)
      handler_list = Array((event[:check][:handlers] || event[:check][:handler]) || 'default')
      handlers = derive_handlers(handler_list)
      handlers.select do |handler|
        if event[:action] == :flapping && !handler[:handle_flapping]
          @logger.info('handler does not handle flapping events', {
            :event => event,
            :handler => handler
          })
          next
        end
        if handler_subdued?(handler, event[:check])
          @logger.info('handler is subdued', {
            :event => event,
            :handler => handler
          })
          next
        end
        if handler.has_key?(:severities)
          handle = case event[:action]
          when :resolve
            event[:check][:history].reverse[1..-1].any? do |status|
              if status.to_i == 0
                break
              end
              severity = SEVERITIES[status.to_i] || 'unknown'
              handler[:severities].include?(severity)
            end
          else
            severity = SEVERITIES[event[:check][:status]] || 'unknown'
            handler[:severities].include?(severity)
          end
          unless handle
            @logger.debug('handler does not handle event severity', {
              :event => event,
              :handler => handler
            })
            next
          end
        end
        if handler.has_key?(:filters) || handler.has_key?(:filter)
          filter_list = Array(handler[:filters] || handler[:filter])
          filtered = filter_list.any? do |filter_name|
            event_filtered?(filter_name, event)
          end
          if filtered
            @logger.info('event filtered for handler', {
              :event => event,
              :handler => handler
            })
            next
          end
        end
        true
      end
    end

    def mutate_event_data(mutator_name, event, &block)
      mutator_name ||= 'json'
      return_output = Proc.new do |output, status|
        if status == 0
          block.dup.call(output)
        else
          @logger.error('mutator error', {
            :event => event,
            :output => output,
            :status => status
          })
          @handlers_in_progress_count -= 1
        end
      end
      @logger.debug('mutating event data', {
        :event => event,
        :mutator_name => mutator_name
      })
      case
      when @settings.mutator_exists?(mutator_name)
        mutator = @settings[:mutators][mutator_name]
        options = {:data => MultiJson.dump(event), :timeout => mutator[:timeout]}
        Spawn.process(mutator[:command], options, &return_output)
      when @extensions.mutator_exists?(mutator_name)
        extension = @extensions[:mutators][mutator_name]
        extension.safe_run(event, &return_output)
      else
        @logger.error('unknown mutator', {
          :mutator_name => mutator_name
        })
        @handlers_in_progress_count -= 1
      end
    end

    def handle_event(event)
      handlers = event_handlers(event)
      handlers.each do |handler|
        log_level = event[:check][:type] == 'metric' ? :debug : :info
        @logger.send(log_level, 'handling event', {
          :event => event,
          :handler => handler.respond_to?(:definition) ? handler.definition : handler
        })
        @handlers_in_progress_count += 1
        on_error = Proc.new do |error|
          @logger.error('handler error', {
            :event => event,
            :handler => handler,
            :error => error.to_s
          })
          @handlers_in_progress_count -= 1
        end
        mutate_event_data(handler[:mutator], event) do |event_data|
          case handler[:type]
          when 'pipe'
            options = {:data => event_data, :timeout => handler[:timeout]}
            Spawn.process(handler[:command], options) do |output, status|
              output.each_line do |line|
                @logger.info('handler output', {
                  :handler => handler,
                  :output => line
                })
              end
              @handlers_in_progress_count -= 1
            end
          when 'tcp'
            begin
              EM::connect(handler[:socket][:host], handler[:socket][:port], SocketHandler) do |socket|
                socket.on_success = Proc.new do
                  @handlers_in_progress_count -= 1
                end
                socket.on_error = on_error
                timeout = handler[:timeout] || 10
                socket.pending_connect_timeout = timeout
                socket.comm_inactivity_timeout = timeout
                socket.send_data(event_data.to_s)
                socket.close_connection_after_writing
              end
            rescue => error
              on_error.call(error)
            end
          when 'udp'
            begin
              EM::open_datagram_socket('0.0.0.0', 0, nil) do |socket|
                socket.send_datagram(event_data.to_s, handler[:socket][:host], handler[:socket][:port])
                socket.close_connection_after_writing
                @handlers_in_progress_count -= 1
              end
            rescue => error
              on_error.call(error)
            end
          when 'transport'
            unless event_data.empty?
              pipe = handler[:pipe]
              @transport.publish(pipe[:type].to_sym, pipe[:name], event_data, pipe[:options] || Hash.new) do |info|
                if info[:error]
                  @logger.fatal('failed to publish event data to the transport', {
                    :pipe => pipe,
                    :payload => event_data,
                    :error => info[:error].to_s
                  })
                end
              end
            end
            @handlers_in_progress_count -= 1
          when 'extension'
            handler.safe_run(event_data) do |output, status|
              output.each_line do |line|
                @logger.info('handler extension output', {
                  :extension => handler.definition,
                  :output => line
                })
              end
              @handlers_in_progress_count -= 1
            end
          end
        end
      end
    end

    def aggregate_result(result)
      @logger.debug('adding result to aggregate', {
        :result => result
      })
      check = result[:check]
      result_set = check[:name] + ':' + check[:issued].to_s
      @redis.hset('aggregation:' + result_set, result[:client], MultiJson.dump(
        :output => check[:output],
        :status => check[:status]
      )) do
        SEVERITIES.each do |severity|
          @redis.hsetnx('aggregate:' + result_set, severity, 0)
        end
        severity = (SEVERITIES[check[:status]] || 'unknown')
        @redis.hincrby('aggregate:' + result_set, severity, 1) do
          @redis.hincrby('aggregate:' + result_set, 'total', 1) do
            @redis.sadd('aggregates:' + check[:name], check[:issued]) do
              @redis.sadd('aggregates', check[:name])
            end
          end
        end
      end
    end

    def event_bridges(event)
      @extensions[:bridges].each do |name, bridge|
        bridge.safe_run(event) do |output, status|
          output.each_line do |line|
            @logger.debug('bridge extension output', {
              :extension => bridge.definition,
              :output => line
            })
          end
        end
      end
    end

    def process_result(result)
      @logger.debug('processing result', {
        :result => result
      })
      @redis.get('client:' + result[:client]) do |client_json|
        unless client_json.nil?
          client = MultiJson.load(client_json)
          check = case
          when @settings.check_exists?(result[:check][:name]) && !result[:check][:standalone]
            @settings[:checks][result[:check][:name]].merge(result[:check])
          else
            result[:check]
          end
          if check[:aggregate]
            aggregate_result(result)
          end
          @redis.sadd('history:' + client[:name], check[:name])
          history_key = 'history:' + client[:name] + ':' + check[:name]
          @redis.rpush(history_key, check[:status]) do
            execution_key = 'execution:' + client[:name] + ':' + check[:name]
            @redis.set(execution_key, check[:executed])
            @redis.lrange(history_key, -21, -1) do |history|
              check[:history] = history
              total_state_change = 0
              unless history.size < 21
                state_changes = 0
                change_weight = 0.8
                previous_status = history.first
                history.each do |status|
                  unless status == previous_status
                    state_changes += change_weight
                  end
                  change_weight += 0.02
                  previous_status = status
                end
                total_state_change = (state_changes.fdiv(20) * 100).to_i
                @redis.ltrim(history_key, -21, -1)
              end
              @redis.hget('events:' + client[:name], check[:name]) do |event_json|
                previous_occurrence = event_json ? MultiJson.load(event_json) : false
                is_flapping = false
                if check.has_key?(:low_flap_threshold) && check.has_key?(:high_flap_threshold)
                  was_flapping = previous_occurrence && previous_occurrence[:action] == 'flapping'
                  is_flapping = case
                  when total_state_change >= check[:high_flap_threshold]
                    true
                  when was_flapping && total_state_change <= check[:low_flap_threshold]
                    false
                  else
                    was_flapping
                  end
                end
                event = {
                  :id => random_uuid,
                  :client => client,
                  :check => check,
                  :occurrences => 1
                }
                if check[:status] != 0 || is_flapping
                  if previous_occurrence && check[:status] == previous_occurrence[:check][:status]
                    event[:occurrences] = previous_occurrence[:occurrences] + 1
                  end
                  event[:action] = is_flapping ? :flapping : :create
                  @redis.hset('events:' + client[:name], check[:name], MultiJson.dump(event)) do
                    unless check[:handle] == false
                      handle_event(event)
                    end
                  end
                elsif previous_occurrence
                  event[:occurrences] = previous_occurrence[:occurrences]
                  event[:action] = :resolve
                  unless check[:auto_resolve] == false && !check[:force_resolve]
                    @redis.hdel('events:' + client[:name], check[:name]) do
                      unless check[:handle] == false
                        handle_event(event)
                      end
                    end
                  end
                elsif check[:type] == 'metric'
                  handle_event(event)
                end
                event_bridges(event)
              end
            end
          end
        end
      end
    end

    def setup_results
      @logger.debug('subscribing to results')
      @transport.subscribe(:direct, 'results', 'results', :ack => true) do |message_info, message|
        begin
          result = MultiJson.load(message)
          @logger.debug('received result', {
            :result => result
          })
          process_result(result)
        rescue MultiJson::ParseError => error
          @logger.error('failed to parse result payload', {
            :message => message,
            :error => error.to_s
          })
        end
        EM::next_tick do
          @transport.ack(message_info)
        end
      end
    end

    def check_request_subdued?(check)
      if check[:subdue] && check[:subdue][:at] == 'publisher'
        action_subdued?(check[:subdue])
      else
        false
      end
    end

    def publish_check_request(check)
      payload = {
        :name => check[:name],
        :issued => Time.now.to_i
      }
      if check.has_key?(:command)
        payload[:command] = check[:command]
      end
      @logger.info('publishing check request', {
        :payload => payload,
        :subscribers => check[:subscribers]
      })
      check[:subscribers].each do |subscription|
        @transport.publish(:fanout, subscription, MultiJson.dump(payload)) do |info|
          if info[:error]
            @logger.error('failed to publish check request', {
              :subscription => subscription,
              :payload => payload,
              :error => info[:error].to_s
            })
          end
        end
      end
    end

    def schedule_checks(checks)
      check_count = 0
      stagger = testing? ? 0 : 2
      checks.each do |check|
        check_count += 1
        scheduling_delay = stagger * check_count % 30
        @timers[:master] << EM::Timer.new(scheduling_delay) do
          interval = testing? ? 0.5 : check[:interval]
          @timers[:master] << EM::PeriodicTimer.new(interval) do
            unless check_request_subdued?(check)
              publish_check_request(check)
            else
              @logger.info('check request was subdued', {
                :check => check
              })
            end
          end
        end
      end
    end

    def setup_publisher
      @logger.debug('scheduling check requests')
      standard_checks = @settings.checks.reject do |check|
        check[:standalone] || check[:publish] == false
      end
      extension_checks = @extensions.checks.reject do |check|
        check[:standalone] || check[:publish] == false || !check[:interval].is_a?(Integer)
      end
      schedule_checks(standard_checks + extension_checks)
    end

    def publish_result(client, check)
      payload = {
        :client => client[:name],
        :check => check
      }
      @logger.debug('publishing check result', {
        :payload => payload
      })
      @transport.publish(:direct, 'results', MultiJson.dump(payload)) do |info|
        if info[:error]
          @logger.error('failed to publish check result', {
            :payload => payload,
            :error => info[:error].to_s
          })
        end
      end
    end

    def determine_stale_clients
      @logger.info('determining stale clients')
      keepalive_check = {
        :thresholds => {
          :warning => 120,
          :critical => 180
        }
      }
      if @settings.handler_exists?(:keepalive)
        keepalive_check[:handler] = "keepalive"
      end
      @redis.smembers('clients') do |clients|
        clients.each do |client_name|
          @redis.get('client:' + client_name) do |client_json|
            unless client_json.nil?
              client = MultiJson.load(client_json)
              check = keepalive_check.dup
              if client.has_key?(:keepalive)
                check = deep_merge(check, client[:keepalive])
              end
              check[:name] = 'keepalive'
              check[:issued] = Time.now.to_i
              check[:executed] = Time.now.to_i
              time_since_last_keepalive = Time.now.to_i - client[:timestamp]
              lag_message = time_since_last_keepalive.to_s
              case
              when time_since_last_keepalive >= check[:thresholds][:critical]
                check[:output] = 'No keep-alive sent from client in over '
                check[:output] << check[:thresholds][:critical].to_s + ' seconds'
                check[:output] << ' (last check ' + lag_message + ' seconds ago)'
                check[:status] = 2
              when time_since_last_keepalive >= check[:thresholds][:warning]
                check[:output] = 'No keep-alive sent from client in over '
                check[:output] << check[:thresholds][:warning].to_s + ' seconds'
                check[:output] << ' (last check ' + lag_message + ' seconds ago)'
                check[:status] = 1
              else
                check[:output] = 'Keep-alive sent from client less than '
                check[:output] << check[:thresholds][:warning].to_s + ' seconds ago'
                check[:output] << ' (last check ' + lag_message + ' seconds ago)'
                check[:status] = 0
              end
              publish_result(client, check)
            end
          end
        end
      end
    end

    def setup_client_monitor
      @logger.debug('monitoring clients')
      @timers[:master] << EM::PeriodicTimer.new(30) do
        determine_stale_clients
      end
    end

    def prune_aggregations
      @logger.info('pruning aggregations')
      @redis.smembers('aggregates') do |checks|
        checks.each do |check_name|
          @redis.smembers('aggregates:' + check_name) do |aggregates|
            if aggregates.size > 20
              aggregates.sort!
              aggregates.take(aggregates.size - 20).each do |check_issued|
                @redis.srem('aggregates:' + check_name, check_issued) do
                  result_set = check_name + ':' + check_issued.to_s
                  @redis.del('aggregate:' + result_set) do
                    @redis.del('aggregation:' + result_set) do
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

    def setup_aggregation_pruner
      @logger.debug('pruning aggregations')
      @timers[:master] << EM::PeriodicTimer.new(20) do
        prune_aggregations
      end
    end

    def master_duties
      setup_publisher
      setup_client_monitor
      setup_aggregation_pruner
    end

    def request_master_election
      @redis.setnx('lock:master', Time.now.to_i) do |created|
        if created
          @is_master = true
          @logger.info('i am the master')
          master_duties
        else
          @redis.get('lock:master') do |timestamp|
            if Time.now.to_i - timestamp.to_i >= 30
              @redis.getset('lock:master', Time.now.to_i) do |previous|
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
      @timers[:run] << EM::Timer.new(2) do
        request_master_election
      end
      @timers[:run] << EM::PeriodicTimer.new(10) do
        if @is_master
          @redis.set('lock:master', Time.now.to_i) do
            @logger.debug('updated master lock timestamp')
          end
        else
          request_master_election
        end
      end
    end

    def resign_as_master
      if @is_master
        @logger.warn('resigning as master')
        @timers[:master].each do |timer|
          timer.cancel
        end
        @timers[:master].clear
        @is_master = false
      else
        @logger.debug('not currently master')
      end
    end

    def unsubscribe
      @logger.warn('unsubscribing from keepalive and result queues')
      @transport.unsubscribe
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

    def bootstrap
      setup_keepalives
      setup_results
      setup_master_monitor
      @state = :running
    end

    def start
      setup_redis
      setup_transport
      bootstrap
    end

    def pause
      unless @state == :pausing || @state == :paused
        @state = :pausing
        @timers[:run].each do |timer|
          timer.cancel
        end
        @timers[:run].clear
        unsubscribe
        resign_as_master
        @state = :paused
      end
    end

    def resume
      retry_until_true(1) do
        if @state == :paused
          if @redis.connected? && @transport.connected?
            bootstrap
            true
          end
        end
      end
    end

    def stop
      @logger.warn('stopping')
      pause
      @state = :stopping
      complete_handlers_in_progress do
        @redis.close
        @transport.close
        super
      end
    end
  end
end
