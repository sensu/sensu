require "sensu/daemon"
require "sensu/server/filter"
require "sensu/server/mutate"
require "sensu/server/handle"

module Sensu
  module Server
    class Process
      include Daemon
      include Filter
      include Mutate
      include Handle

      attr_reader :is_master, :handling_event_count

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
        @handling_event_count = 0
      end

      def update_client_registry(client, &callback)
        @logger.debug("updating client registry", :client => client)
        @redis.set("client:#{client[:name]}", MultiJson.dump(client)) do
          @redis.sadd("clients", client[:name]) do
            callback.call
          end
        end
      end

      def setup_keepalives
        @logger.debug("subscribing to keepalives")
        @transport.subscribe(:direct, "keepalives", "keepalives", :ack => true) do |message_info, message|
          @logger.debug("received keepalive", :message => message)
          begin
            client = MultiJson.load(message)
            update_client_registry(client) do
              @transport.ack(message_info)
            end
          rescue MultiJson::ParseError => error
            @logger.error("failed to parse keepalive payload", {
              :message => message,
              :error => error.to_s
            })
            @transport.ack(message_info)
          end
        end
      end

      def expand_handler_sets(handler, depth=0)
        if handler[:type] == "set"
          if depth < 2
            derive_handlers(handler[:handlers], depth + 1)
          else
            @logger.error("handler sets cannot be deeply nested", :handler => handler)
            nil
          end
        else
          handler
        end
      end

      def derive_handlers(handler_list, depth=0)
        handler_list.compact.map { |handler_name|
          case
          when @settings.handler_exists?(handler_name)
            handler = @settings[:handlers][handler_name].merge(:name => handler_name)
            expand_handler_sets(handler, depth)
          when @extensions.handler_exists?(handler_name)
            @extensions[:handlers][handler_name]
          else
            @logger.error("unknown handler", :handler_name => handler_name)
            nil
          end
        }.flatten.compact.uniq
      end

      def event_bridges(event)
        @extensions[:bridges].each do |name, bridge|
          bridge.safe_run(event) do |output, status|
            @logger.debug("bridge extension output", {
              :extension => bridge.definition,
              :output => output
            })
          end
        end
      end

      def process_event(event)
        log_level = event[:check][:type] == "metric" ? :debug : :info
        @logger.send(log_level, "processing event", :event => event)
        event_bridges(event)
        handler_list = Array((event[:check][:handlers] || event[:check][:handler]) || "default")
        handlers = derive_handlers(handler_list)
        handlers.each do |handler|
          @handling_event_count += 1
          filter_event(handler, event) do |event|
            mutate_event(handler, event) do |event_data|
              handle_event(handler, event_data)
            end
          end
        end
      end

      def aggregate_check_result(result)
        @logger.debug("adding check result to aggregate", :result => result)
        check = result[:check]
        result_set = "#{check[:name]}:#{check[:issued]}"
        result_data = MultiJson.dump(:output => check[:output], :status => check[:status])
        @redis.hset("aggregation:#{result_set}", result[:client], result_data) do
          SEVERITIES.each do |severity|
            @redis.hsetnx("aggregate:#{result_set}", severity, 0)
          end
          severity = (SEVERITIES[check[:status]] || "unknown")
          @redis.hincrby("aggregate:#{result_set}", severity, 1) do
            @redis.hincrby("aggregate:#{result_set}", "total", 1) do
              @redis.sadd("aggregates:#{check[:name]}", check[:issued]) do
                @redis.sadd("aggregates", check[:name])
              end
            end
          end
        end
      end

      def store_check_result(client, check, &callback)
        @redis.sadd("history:#{client[:name]}", check[:name]) do
          result_key = "#{client[:name]}:#{check[:name]}"
          history_key = "history:#{result_key}"
          @redis.rpush(history_key, check[:status]) do
            @redis.set("execution:#{result_key}", check[:executed])
            @redis.ltrim(history_key, -21, -1)
            callback.call
          end
        end
      end

      def check_history(client, check, &callback)
        history_key = "history:#{client[:name]}:#{check[:name]}"
        @redis.lrange(history_key, -21, -1) do |history|
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
          end
          callback.call(history, total_state_change)
        end
      end

      def check_flapping?(stored_event, check)
        if check.has_key?(:low_flap_threshold) && check.has_key?(:high_flap_threshold)
          was_flapping = stored_event && stored_event[:action] == "flapping"
          check[:total_state_change] >= check[:high_flap_threshold] ||
            (was_flapping && check[:total_state_change] <= check[:low_flap_threshold]) ||
            was_flapping
        else
          false
        end
      end

      def update_event_registry(client, check, &callback)
        @redis.hget("events:#{client[:name]}", check[:name]) do |event_json|
          stored_event = event_json ? MultiJson.load(event_json) : nil
          flapping = check_flapping?(stored_event, check)
          event = {
            :id => random_uuid,
            :client => client,
            :check => check,
            :occurrences => 1
          }
          if check[:status] != 0 || flapping
            if stored_event && check[:status] == stored_event[:check][:status]
              event[:occurrences] = stored_event[:occurrences] + 1
            end
            event[:action] = flapping ? :flapping : :create
            @redis.hset("events:#{client[:name]}", check[:name], MultiJson.dump(event)) do
              callback.call(event)
            end
          elsif stored_event
            event[:occurrences] = stored_event[:occurrences]
            event[:action] = :resolve
            unless check[:auto_resolve] == false && !check[:force_resolve]
              @redis.hdel("events:#{client[:name]}", check[:name]) do
                callback.call(event)
              end
            end
          elsif check[:type] == "metric"
            callback.call(event)
          end
        end
      end

      def process_check_result(result)
        @logger.debug("processing result", :result => result)
        @redis.get("client:#{result[:client]}") do |client_json|
          unless client_json.nil?
            client = MultiJson.load(client_json)
            check = case
            when @settings.check_exists?(result[:check][:name]) && !result[:check][:standalone]
              @settings[:checks][result[:check][:name]].merge(result[:check])
            else
              result[:check]
            end
            aggregate_check_result(result) if check[:aggregate]
            store_check_result(client, check) do
              check_history(client, check) do |history, total_state_change|
                check[:history] = history
                check[:total_state_change] = total_state_change
                update_event_registry(client, check) do |event|
                  process_event(event)
                end
              end
            end
          else
            @logger.warn("client not in registry", :client => result[:client])
          end
        end
      end

      def setup_results
        @logger.debug("subscribing to results")
        @transport.subscribe(:direct, "results", "results", :ack => true) do |message_info, message|
          begin
            result = MultiJson.load(message)
            @logger.debug("received result", :result => result)
            process_check_result(result)
          rescue MultiJson::ParseError => error
            @logger.error("failed to parse result payload", {
              :message => message,
              :error => error.to_s
            })
          end
          EM::next_tick do
            @transport.ack(message_info)
          end
        end
      end

      def publish_check_request(check)
        payload = {
          :name => check[:name],
          :issued => Time.now.to_i
        }
        payload[:command] = check[:command] if check.has_key?(:command)
        @logger.info("publishing check request", {
          :payload => payload,
          :subscribers => check[:subscribers]
        })
        check[:subscribers].each do |subscription|
          @transport.publish(:fanout, subscription, MultiJson.dump(payload)) do |info|
            if info[:error]
              @logger.error("failed to publish check request", {
                :subscription => subscription,
                :payload => payload,
                :error => info[:error].to_s
              })
            end
          end
        end
      end

      def calculate_check_execution_splay(check)
        splay_hash = Digest::MD5.digest(check[:name]).unpack('Q<').first
        current_time = (Time.now.to_f * 1000).to_i
        (splay_hash - current_time) % (check[:interval] * 1000) / 1000.0
      end

      def schedule_check_executions(checks)
        checks.each do |check|
          create_check_request = Proc.new do
            unless check_request_subdued?(check)
              publish_check_request(check)
            else
              @logger.info("check request was subdued", :check => check)
            end
          end
          execution_splay = testing? ? 0 : calculate_check_execution_splay(check)
          interval = testing? ? 0.5 : check[:interval]
          @timers[:master] << EM::Timer.new(execution_splay) do
            create_check_request.call
            @timers[:master] << EM::PeriodicTimer.new(interval, &create_check_request)
          end
        end
      end

      def setup_check_request_publisher
        @logger.debug("scheduling check requests")
        standard_checks = @settings.checks.reject do |check|
          check[:standalone] || check[:publish] == false
        end
        extension_checks = @extensions.checks.reject do |check|
          check[:standalone] || check[:publish] == false || !check[:interval].is_a?(Integer)
        end
        schedule_check_executions(standard_checks + extension_checks)
      end

      def publish_check_result(client, check)
        payload = {
          :client => client[:name],
          :check => check
        }
        @logger.debug("publishing check result", :payload => payload)
        @transport.publish(:direct, "results", MultiJson.dump(payload)) do |info|
          if info[:error]
            @logger.error("failed to publish check result", {
              :payload => payload,
              :error => info[:error].to_s
            })
          end
        end
      end

      def create_keepalive_check(client)
        check = {
          :thresholds => {
            :warning => 120,
            :critical => 180
          }
        }
        if @settings.handler_exists?(:keepalive)
          check[:handler] = "keepalive"
        end
        if client.has_key?(:keepalive)
          check = deep_merge(check, client[:keepalive])
        end
        timestamp = Time.now.to_i
        check.merge(:name => "keepalive", :issued => timestamp, :executed => timestamp)
      end

      def determine_stale_clients
        @logger.info("determining stale clients")
        @redis.smembers("clients") do |clients|
          clients.each do |client_name|
            @redis.get("client:#{client_name}") do |client_json|
              unless client_json.nil?
                client = MultiJson.load(client_json)
                check = create_keepalive_check(client)
                time_since_last_keepalive = Time.now.to_i - client[:timestamp]
                check[:output] = "No keepalive sent from client for "
                check[:output] << "#{time_since_last_keepalive} seconds"
                case
                when time_since_last_keepalive >= check[:thresholds][:critical]
                  check[:output] << " (>=#{check[:thresholds][:critical]})"
                  check[:status] = 2
                when time_since_last_keepalive >= check[:thresholds][:warning]
                  check[:output] << " (>=#{check[:thresholds][:warning]})"
                  check[:status] = 1
                else
                  check[:output] = "Keepalive sent from client "
                  check[:output] << "#{time_since_last_keepalive} seconds ago"
                  check[:status] = 0
                end
                publish_check_result(client, check)
              end
            end
          end
        end
      end

      def setup_client_monitor
        @logger.debug("monitoring client keepalives")
        @timers[:master] << EM::PeriodicTimer.new(30) do
          determine_stale_clients
        end
      end

      def prune_check_result_aggregations
        @logger.info("pruning check result aggregations")
        @redis.smembers("aggregates") do |checks|
          checks.each do |check_name|
            @redis.smembers("aggregates:#{check_name}") do |aggregates|
              if aggregates.size > 20
                aggregates.sort!
                aggregates.take(aggregates.size - 20).each do |check_issued|
                  @redis.srem("aggregates:#{check_name}", check_issued) do
                    result_set = "#{check_name}:#{check_issued}"
                    @redis.del("aggregate:#{result_set}") do
                      @redis.del("aggregation:#{result_set}") do
                        @logger.debug("pruned aggregation", {
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

      def setup_check_result_aggregation_pruner
        @logger.debug("pruning check result aggregations")
        @timers[:master] << EM::PeriodicTimer.new(20) do
          prune_check_result_aggregations
        end
      end

      def master_duties
        setup_check_request_publisher
        setup_client_monitor
        setup_check_result_aggregation_pruner
      end

      def request_master_election
        @redis.setnx("lock:master", Time.now.to_i) do |created|
          if created
            @is_master = true
            @logger.info("i am the master")
            master_duties
          else
            @redis.get("lock:master") do |timestamp|
              if Time.now.to_i - timestamp.to_i >= 30
                @redis.getset("lock:master", Time.now.to_i) do |previous|
                  if previous == timestamp
                    @is_master = true
                    @logger.info("i am now the master")
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
            @redis.set("lock:master", Time.now.to_i) do
              @logger.debug("updated master lock timestamp")
            end
          else
            request_master_election
          end
        end
      end

      def resign_as_master
        if @is_master
          @logger.warn("resigning as master")
          @timers[:master].each do |timer|
            timer.cancel
          end
          @timers[:master].clear
          @is_master = false
        else
          @logger.debug("not currently master")
        end
      end

      def unsubscribe
        @logger.warn("unsubscribing from keepalive and result queues")
        @transport.unsubscribe
      end

      def complete_event_handling(&block)
        @logger.info("completing event handling in progress", {
          :handling_event_count => @handling_event_count
        })
        retry_until_true do
          if @handling_event_count == 0
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
        @logger.warn("stopping")
        pause
        @state = :stopping
        complete_event_handling do
          @redis.close
          @transport.close
          super
        end
      end

    end
  end
end
