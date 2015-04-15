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

      # Create an instance of the Sensu server process, start the
      # server within the EventMachine event loop, and set up server
      # process signal traps (for stopping).
      #
      # @param options [Hash]
      def self.run(options={})
        server = self.new(options)
        EM::run do
          server.start
          server.setup_signal_traps
        end
      end

      # Override Daemon initialize() to support Sensu server master
      # election and the handling event count.
      #
      # @param options [Hash]
      def initialize(options={})
        super
        @is_master = false
        @timers[:master] = Array.new
        @handling_event_count = 0
      end

      # Update the Sensu client registry, stored in Redis. Sensu
      # client data is used to provide additional event context and
      # enable agent health monitoring. JSON serialization is used for
      # the client data.
      #
      # @param client [Hash]
      # @param callback [Proc] to call after the the client data has
      #   been added to (or updated) the registry.
      def update_client_registry(client, &callback)
        @logger.debug("updating client registry", :client => client)
        @redis.set("client:#{client[:name]}", MultiJson.dump(client)) do
          @redis.sadd("clients", client[:name]) do
            callback.call
          end
        end
      end

      # Set up the client keepalive consumer, keeping the Sensu client
      # registry updated. The consumer receives JSON serialized client
      # keepalives from the transport, parses them, and calls
      # `update_client_registry()` with the client data to update the
      # registry. Transport message acknowledgements are used to
      # ensure the client registry is updated successfully. Keepalive
      # JSON parsing errors are logged.
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

      # Expand event handler sets, creating an array of handler
      # definitions. Handler sets cannot be deeply nested (by choice),
      # this method will return `nil` if an attempt is made to deeply
      # nest. If the provided handler definition is not a set, it is
      # returned.
      #
      # @param handler [Hash] definition.
      # @param depth [Integer] of the expansion.
      # @return [Array, Hash, Nil]
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

      # Derive an array of handler definitions from a list of handler
      # names. This method first checks for the existence of standard
      # handlers, followed by handler extensions. If a handler does
      # not exist for a name, it is logged and ignored. Duplicate
      # handler definitions are removed.
      #
      # @param handler_list [Array]
      # @param depth [Integer] of handler set expansion.
      # @return [Array]
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

      # Run event bridge extensions, within the Sensu EventMachine
      # reactor (event loop). The extension API `safe_run()` method is
      # used to guard against most errors. Bridges are for relaying
      # Sensu event data to other services.
      #
      # @param event [Hash]
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

      # Process an event: filter -> mutate -> handle.
      #
      # This method runs event bridges, relaying the event data to
      # other services. This method also determines the appropriate
      # handlers for the event, filtering and mutating the event data
      # for each of them. The `@handling_event_count` is incremented
      # by `1`, for each event handler chain (filter -> mutate ->
      # handle).
      #
      # @param event [Hash]
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

      # Add a check result to an aggregate. A check aggregate uses the
      # check `:name` and the `:issued` timestamp as its unique
      # identifier. An aggregate uses several counters: the total
      # number of results in the aggregate, and a counter for each
      # check severity (ok, warning, etc). Check output is also
      # stored, to be summarized to aid in identifying outliers for a
      # check execution across a number of Sensu clients. JSON
      # serialization is used for storing check result data.
      #
      # @param result [Hash]
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

      # Store check result data. This method stores check result data
      # and the 21 most recent check result statuses for a client/check
      # pair, this history is used for event context and flap detection.
      # The check execution timestamp is also stored, to provide an
      # indication of how recent the data is.
      #
      # @param client [Hash]
      # @param check [Hash]
      # @param callback [Proc] to call when the check result data has
      #   been stored (history, etc).
      def store_check_result(client, check, &callback)
        @logger.debug("storing check result", :check => check)
        @redis.sadd("result:#{client[:name]}", check[:name])
        result_key = "#{client[:name]}:#{check[:name]}"
        check_truncated = check.merge(:output => check[:output][0..256])
        @redis.set("result:#{result_key}", MultiJson.dump(check_truncated)) do
          history_key = "history:#{result_key}"
          @redis.rpush(history_key, check[:status]) do
            @redis.ltrim(history_key, -21, -1)
            callback.call
          end
        end
      end

      # Fetch the execution history for a client/check pair, the 21
      # most recent check result statuses. This method also calculates
      # the total state change percentage for the history, this value
      # is use for check state flap detection, using a similar
      # algorithm to Nagios:
      # http://nagios.sourceforge.net/docs/3_0/flapping.html
      #
      # @param client [Hash]
      # @param check [Hash]
      # @param callback [Proc] to be called with the check history and
      #   total state change value.
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

      # Determine if a check state is flapping, rapidly changing
      # between an OK and non-OK state. Flap detection is only done
      # for checks that have defined low and hight flap detection
      # thresholds, `:low_flap_threshold` and `:high_flap_threshold`.
      # The `check_history()` method provides the check history and
      # more importantly the total state change precentage value that
      # is compared with the configured thresholds defined in the
      # check data. If a check hasn't been flapping, the
      # `:total_state_change` must be equal to or higher than the
      # `:high_flap_threshold` to be changed to flapping. If a check
      # has been flapping, the `:total_state_change` must be equal to
      # or lower than the `:low_flap_threshold` to no longer be
      # flapping. This method uses the same algorithm as Nagios:
      # http://nagios.sourceforge.net/docs/3_0/flapping.html
      #
      # @param stored_event [Hash]
      # @param check [Hash]
      # @return [TrueClass, FalseClass]
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

      # Update the event registry, stored in Redis. This method
      # determines if check data results in the creation or update of
      # event data in the registry. Existing event data for a
      # client/check pair is fetched, used in conditionals and the
      # composition of the new event data. If a check `:status` is not
      # `0`, or it has been flapping, an event is created/updated in
      # the registry. If there was existing event data, but the check
      # `:status` is now `0`, the event is removed (resolved) from the
      # registry. If the previous conditions are not met, and check
      # `:type` is `metric` and the `:status` is `0`, the event
      # registry is not updated, but the provided callback is called
      # with the event data. JSON serialization is used when storing
      # data in the registry.
      #
      # @param client [Hash]
      # @param check [Hash]
      # @param callback [Proc] to be called with the resulting event
      #   data if the event registry is updated, or the check is of
      #   type `:metric`.
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

      # Process a check result, storing its data, inspecting its
      # contents, and taking the appropriate actions (eg. update the
      # event registry). A check result must have a valid client name,
      # associated with a client in the registry. Results without a
      # valid client are discarded, to keep the system "correct". If a
      # local check definition exists for the check name, and the
      # check result is not from a standalone check execution, it's
      # merged with the check result for more context.
      #
      # @param result [Hash] data.
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

      # Set up the check result consumer. The consumer receives JSON
      # serialized check results from the transport, parses them, and
      # calls `process_check_result()` with the result data to be
      # processed. Transport message acknowledgements are used to
      # ensure that results make it to processing. The transport
      # message acknowledgements are currently done in the next tick
      # of the EventMachine reactor (event loop), as a flow control
      # mechanism. Result JSON parsing errors are logged.
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

      # Publish a check request to the transport. A check request is
      # composted of a check `:name`, an `:issued` timestamp, and a
      # check `:command` if available. The check request is published
      # to a transport pipe, for each of the check `:subscribers` in
      # its definition, eg. "webserver". JSON serialization is used
      # when publishing the check request payload to the transport
      # pipes. Transport errors are logged.
      #
      # @param check [Hash] definition.
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

      # Calculate a check execution splay, taking into account the
      # current time and the execution interval to ensure it's
      # consistent between process restarts.
      #
      # @param check [Hash] definition.
      def calculate_check_execution_splay(check)
        splay_hash = Digest::MD5.digest(check[:name]).unpack('Q<').first
        current_time = (Time.now.to_f * 1000).to_i
        (splay_hash - current_time) % (check[:interval] * 1000) / 1000.0
      end

      # Schedule check executions, using EventMachine periodic timers,
      # using a calculated execution splay. The timers are stored in
      # the timers hash under `:master`, as check request publishing
      # is a task for only the Sensu server master, so they can be
      # cancelled etc. Check requests are not published if subdued.
      #
      # @param checks [Array] of definitions.
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

      # Set up the check request publisher. This method creates an
      # array of check definitions, that are not standalone checks,
      # and do not have `:publish` set to `false`. The array of check
      # definitions includes those from standard checks and extensions
      # (with a defined execution `:interval`). The array is provided
      # to the `schedule_check_executions()` method.
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

      # Publish a check result to the transport for processing. A
      # check result is composed of a client name and a check
      # definition, containing check `:output` and `:status`. JSON
      # serialization is used when publishing the check result payload
      # to the transport pipe. Transport errors are logged.
      #
      # @param client [Hash]
      # @param check [Hash]
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

      # Create a keepalive check definition for a client. Client
      # definitions may contain `:keepalive` configuration, containing
      # specific thresholds and handler information. The keepalive
      # check definition creation begins with default thresholds, and
      # sets the `:handler` to `keepalive`, if the handler has a local
      # definition. If the client provides its own `:keepalive`
      # configuration, it's deep merged with the defaults. The check
      # `:name`, `:issued`, and `:executed` values are always
      # overridden to guard against an invalid definition.
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

      # Determine stale clients, those that have not sent a keepalive
      # in a specified amount of time (thresholds). This method
      # iterates through the client registry, creating a keepalive
      # check definition with the `create_keepalive_check()` method,
      # containing client specific staleness thresholds. If the time
      # since the latest keepalive is equal to or greater than a
      # threshold, the check `:output` is set to a descriptive
      # message, and `:status` is set to the appropriate non-zero
      # value. If a client has been sending keepalives, `:output` and
      # `:status` are set to indicate an OK state. A check result is
      # published for every client in the registry.
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

      # Set up the client monitor, a periodic timer to run
      # `determine_stale_clients()` every 30 seconds. The timer is
      # stored in the timers hash under `:master`.
      def setup_client_monitor
        @logger.debug("monitoring client keepalives")
        @timers[:master] << EM::PeriodicTimer.new(30) do
          determine_stale_clients
        end
      end

      # Prune check result aggregations (aggregates). Sensu only
      # stores the 20 latest aggregations for a check, to keep the
      # amount of data stored to a minimum.
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

      # Set up the check result aggregation pruner, using periodic
      # timer to run `prune_check_result_aggregations()` every 20
      # seconds. The timer is stored in the timers hash under
      # `:master`.
      def setup_check_result_aggregation_pruner
        @logger.debug("pruning check result aggregations")
        @timers[:master] << EM::PeriodicTimer.new(20) do
          prune_check_result_aggregations
        end
      end

      # Set up the master duties, tasks only performed by a single
      # Sensu server at a time. The duties include publishing check
      # requests, monitoring for stale clients, and pruning check
      # result aggregations.
      def master_duties
        setup_check_request_publisher
        setup_client_monitor
        setup_check_result_aggregation_pruner
      end

      # Request a master election, a process to determine if the
      # current process is the master Sensu server, with its
      # own/unique duties. A Redis key/value is used as a central
      # lock, using the "SETNX" Redis command to set the key/value if
      # it does not exist, using a timestamp for the value. If the
      # current process was able to create the key/value, it is the
      # master, and must do the duties of the master. If the current
      # process was not able to create the key/value, but the current
      # timestamp value is equal to or over 30 seconds ago, the
      # "GETSET" Redis command is used to set a new timestamp and
      # fetch the previous value to compare them, to determine if it
      # was set by the current process. If the current process is able
      # to set the timestamp value, it becomes the master. The master
      # has `@is_master` set to `true`.
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

      # Set up the master monitor. A one-time timer is used to run
      # `request_master_exection()` in 2 seconds. A periodic timer is
      # used to update the master lock timestamp if the current
      # process is the master, or to run `request_master_election(),
      # every 10 seconds. The timers are stored in the timers hash
      # under `:run`.
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

      # Resign as master, if the current process is the Sensu server
      # master. This method cancels and clears the master timers,
      # those with references stored in the timers hash under
      # `:master`, and `@is_master`is set to `false`.
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

      # Unsubscribe from transport subscriptions (all of them). This
      # method is called when there are issues with connectivity, or
      # the process is stopping.
      def unsubscribe
        @logger.warn("unsubscribing from keepalive and result queues")
        @transport.unsubscribe
      end

      # Complete event handling currently in progress. The
      # `:handling_event_count` is used to determine if event handling
      # is complete, when it is equal to `0`. The provided callback is
      # called when handling is complete.
      #
      # @param callback [Proc] to call when event handling is
      #   complete.
      def complete_event_handling(&callback)
        @logger.info("completing event handling in progress", {
          :handling_event_count => @handling_event_count
        })
        retry_until_true do
          if @handling_event_count == 0
            callback.call
            true
          end
        end
      end

      # Bootstrap the Sensu server process, setting up the keepalive
      # and check result consumers, and attemping to become the master
      # to carry out its duties. This method sets the process/daemon
      # `@state` to `:running`.
      def bootstrap
        setup_keepalives
        setup_results
        setup_master_monitor
        @state = :running
      end

      # Start the Sensu server process, connecting to Redis, the
      # transport, and calling the `bootstrap()` method.
      def start
        setup_redis
        setup_transport
        bootstrap
      end

      # Pause the Sensu server process, unless it is being paused or
      # has already been paused. The process/daemon `@state` is first
      # set to `:pausing`, to indicate that it's in progress. All run
      # timers are cancelled, and the references are cleared. The
      # Sensu server will unsubscribe from all transport
      # subscriptions, resign as master (if currently the master),
      # then set the process/daemon `@state` to `:paused`.
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

      # Resume the Sensu server process if it is currently or will
      # soon be paused. The `retry_until_true` helper method is used
      # to determine if the process is paused and if the Redis and
      # transport connections are connected. If the conditions are
      # met, `bootstrap()` will be called and true is returned to stop
      # `retry_until_true`.
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

      # Stop the Sensu server process, pausing it, completing event
      # handling in progress, closing the Redis and transport
      # connections, and exiting the process (exit 0). After pausing
      # the process, the process/daemon `@state` is set to
      # `:stopping`.
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
