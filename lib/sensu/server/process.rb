require "sensu/daemon"
require "sensu/server/filter"
require "sensu/server/mutate"
require "sensu/server/handle"
require "sensu/server/tessen"

module Sensu
  module Server
    class Process
      include Daemon
      include Filter
      include Mutate
      include Handle

      attr_reader :tasks, :in_progress

      TASKS = ["check_request_publisher", "client_monitor", "check_result_monitor"]

      STANDARD_CHECK_TYPE = "standard".freeze

      METRIC_CHECK_TYPE = "metric".freeze

      EVENT_FLAPPING_ACTION = "flapping".freeze

      DEFAULT_HANDLER_NAME = "default".freeze

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

      # Override Daemon initialize() to support Sensu server tasks and
      # the handling event count.
      #
      # @param options [Hash]
      def initialize(options={})
        super
        @tasks = []
        @timers[:tasks] = {}
        TASKS.each do |task|
          @timers[:tasks][task.to_sym] = []
        end
        @in_progress = Hash.new(0)
      end

      # Set up the Redis and Transport connection objects, `@redis`
      # and `@transport`. This method updates the Redis on error
      # callback to reset the in progress check result counter. This
      # method "drys" up many instances of `setup_redis()` and
      # `setup_transport()`, particularly in the specs.
      #
      # @yield callback/block called after connecting to Redis and the
      #   Sensu Transport.
      def setup_connections
        setup_redis do
          @redis.on_error do |error|
            @logger.error("redis connection error", :error => error.to_s)
            @in_progress[:check_results] = 0
          end
          setup_transport do
            yield
          end
        end
      end

      # Create a registration check definition for a client. Client
      # definitions may contain `:registration` configuration,
      # containing custom attributes and handler information. By
      # default, the registration check definition sets the `:handler`
      # to `registration`. If the client provides its own
      # `:registration` configuration, it's deep merged with the
      # defaults. The check `:name`, `:output`, `:issued`, and
      # `:executed` values are always overridden to guard against an
      # invalid definition.
      def create_registration_check(client)
        check = {:handler => "registration", :status => 1}
        if client.has_key?(:registration)
          check = deep_merge(check, client[:registration])
        end
        timestamp = Time.now.to_i
        overrides = {
          :name => "registration",
          :output => "new client registration",
          :issued => timestamp,
          :executed => timestamp
        }
        check.merge(overrides)
      end

      # Create and process a client registration event. A registration
      # event is created when a Sensu client is first added to the
      # client registry. The `create_registration_check()` method is
      # called to create a registration check definition for the
      # client.
      #
      # @param client [Hash] definition.
      def create_client_registration_event(client)
        check = create_registration_check(client)
        create_event(client, check) do |event|
          event_bridges(event)
          process_event(event)
        end
      end

      # Process an initial client registration, when it is first added
      # to the client registry. If a registration handler is defined
      # or the client specifies one, a client registration event is
      # created and processed (handled, etc.) for the client
      # (`create_client_registration_event()`).
      #
      # @param client [Hash] definition.
      def process_client_registration(client)
        if @settings.handler_exists?("registration") || client[:registration]
          create_client_registration_event(client)
        end
      end

      # Update the Sensu client registry, stored in Redis. Sensu
      # client data is used to provide additional event context and
      # enable agent health monitoring.
      #
      # To enable silencing individual clients, per-client
      # subscriptions (`client:$CLIENT_NAME`) are added to client
      # subscriptions automatically.
      #
      # The client registry supports client signatures, unique string
      # identifiers used for keepalive and result source
      # verification. If a client has a signature, all further
      # registry updates for the client must have the same
      # signature. A client can begin to use a signature if one was
      # not previously configured. JSON serialization is used for the
      # stored client data.
      #
      # @param client [Hash]
      # @yield [success] passes success status to optional
      #   callback/block.
      # @yieldparam success [TrueClass,FalseClass] indicating if the
      #   client registry update was a success or the client data was
      #   discarded due to client signature mismatch.
      def update_client_registry(client)
        @logger.debug("updating client registry", :client => client)
        client_key = "client:#{client[:name]}"
        client[:subscriptions] = (client[:subscriptions] + [client_key]).uniq
        signature_key = "#{client_key}:signature"
        @redis.setnx(signature_key, client[:signature]) do |created|
          process_client_registration(client) if created
          @redis.get(signature_key) do |signature|
            if (signature.nil? || signature.empty?) && client[:signature]
              @redis.set(signature_key, client[:signature])
            end
            if signature.nil? || signature.empty? || client[:signature] == signature
              @redis.multi
              @redis.set(client_key, Sensu::JSON.dump(client))
              @redis.sadd("clients", client[:name])
              @redis.exec do
                yield(true) if block_given?
              end
            else
              @logger.warn("invalid client signature", {
                :client => client,
                :signature => signature
              })
              @logger.warn("not updating client in the registry", :client => client)
              yield(false) if block_given?
            end
          end
        end
      end

      # Determine if a transport message is under the optional
      # configured max message size. This method helps prevent
      # oversized messages from consuming memory and being persisted
      # to the datastore.
      #
      # @param message [String]
      # @return [TrueClass,FalseClass]
      def message_size_ok?(message)
        if @settings[:sensu][:server] &&
           @settings[:sensu][:server][:max_message_size]
          message_size = message.bytesize
          max_message_size = @settings[:sensu][:server][:max_message_size]
          if message_size <= max_message_size
            true
          else
            @logger.error("message exceeds the configured max message size", {
              :max_message_size => max_message_size,
              :message_size => message_size,
              :message => message
            })
            false
          end
        else
          true
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
        keepalives_pipe = "keepalives"
        if @settings[:sensu][:server] && @settings[:sensu][:server][:keepalives_pipe]
          keepalives_pipe = @settings[:sensu][:server][:keepalives_pipe]
        end
        @logger.debug("subscribing to keepalives", :pipe => keepalives_pipe)
        @transport.subscribe(:direct, keepalives_pipe, "keepalives", :ack => true) do |message_info, message|
          @logger.debug("received keepalive", :message => message)
          if message_size_ok?(message)
            begin
              client = Sensu::JSON.load(message)
              update_client_registry(client)
            rescue Sensu::JSON::ParseError => error
              @logger.error("failed to parse keepalive payload", {
                :message => message,
                :error => error.to_s
              })
            end
          end
          EM::next_tick do
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

      # Process an event: filter -> mutate -> handle.
      #
      # This method determines the appropriate handlers for an event,
      # filtering and mutating the event data for each of them. The
      # `@in_progress[:events]` counter is incremented by `1`, for
      # each event handler chain (filter -> mutate -> handle).
      #
      # @param event [Hash]
      def process_event(event)
        log_level = event[:check][:type] == METRIC_CHECK_TYPE ? :debug : :info
        @logger.send(log_level, "processing event", :event => event)
        handler_list = Array((event[:check][:handlers] || event[:check][:handler]) || DEFAULT_HANDLER_NAME)
        handlers = derive_handlers(handler_list)
        handlers.each do |handler|
          @in_progress[:events] += 1
          filter_event(handler, event) do |event|
            mutate_event(handler, event) do |event_data|
              handle_event(handler, event_data, event[:id])
            end
          end
        end
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

      # Add a check result to one or more aggregates. The aggregate name is
      # determined by the value of check `:aggregates` array, if present,
      # and falling back to `:aggregate` otherwise.
      #
      # When one or more aggregates are specified as `:aggregates`, the
      # client name and check are updated on each aggregate.
      #
      # When no aggregates are specified as `:aggregates`, and `:aggregate`
      # is `true` (legacy), the check `:name` is used as the aggregate name.
      #
      # When no aggregates are specified as `:aggregates` and check `:aggregate`
      # is a string, it used as the aggregate name.
      #
      # This method will add the client name to configured aggregates, all
      # other processing (e.g. counters) is done by the Sensu API on request.
      #
      # @param client [Hash]
      # @param check [Hash]
      def aggregate_check_result(client, check)
        check_aggregate = (check[:aggregate].is_a?(String) ? check[:aggregate] : check[:name])
        aggregate_list = Array(check[:aggregates] || check_aggregate)
        aggregate_list.each do |aggregate|
          @logger.debug("adding check result to aggregate", {
            :aggregate => aggregate,
            :client => client,
            :check => check
          })
          aggregate_member = "#{client[:name]}:#{check[:name]}"
          @redis.sadd("aggregates:#{aggregate}", aggregate_member) do
            @redis.sadd("aggregates", aggregate)
          end
        end
      end

      # Truncate check output. Metric checks (`"type": "metric"`), or
      # checks with `"truncate_output": true`, have their output
      # truncated to a single line and a maximum character length of
      # 255 by default. The maximum character length can be change by
      # the `"truncate_output_length"` check definition attribute.
      #
      # @param check [Hash]
      # @return [Hash] check with truncated output.
      def truncate_check_output(check)
        if check[:truncate_output] ||
           (check[:type] == METRIC_CHECK_TYPE && check[:truncate_output] != false)
          begin
            output_lines = check[:output].split("\n")
          rescue ArgumentError
            utf8_output = check[:output].encode("UTF-8", "binary", {
              :invalid => :replace,
              :undef => :replace,
              :replace => ""
            })
            output_lines = utf8_output.split("\n")
          end
          output = output_lines.first || check[:output]
          truncate_output_length = check.fetch(:truncate_output_length, 255)
          if output_lines.length > 1 || output.length > truncate_output_length
            output = output[0..truncate_output_length] + "\n..."
          end
          check.merge(:output => output)
        else
          check
        end
      end

      # Store check result data. This method stores check result data
      # and the 21 most recent check result statuses for a client/check
      # pair, this history is used for event context and flap detection.
      # The check execution timestamp is also stored, to provide an
      # indication of how recent the data is. Check output is
      # truncated by `truncate_check_output()` before it is stored.
      #
      # @param client [Hash]
      # @param check [Hash]
      # @yield [] callback/block called after the check data has been
      #   stored (history, etc).
      def store_check_result(client, check)
        @logger.debug("storing check result", :check => check)
        result_key = "#{client[:name]}:#{check[:name]}"
        history_key = "history:#{result_key}"
        check_truncated = truncate_check_output(check)
        @redis.multi
        @redis.sadd("result:#{client[:name]}", check[:name])
        @redis.set("result:#{result_key}", Sensu::JSON.dump(check_truncated))
        @redis.sadd("ttl", result_key) if check[:ttl]
        @redis.rpush(history_key, check[:status])
        @redis.ltrim(history_key, -21, -1)
        if check[:status] == 0
          @redis.set("#{history_key}:last_ok", check.fetch(:executed, Time.now.to_i))
        end
        @redis.exec do
          yield
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
      # @yield [history, total_state_change] callback/block to call
      #   with the check history and calculated total state change
      #   value.
      # @yieldparam history [Array] containing the last 21 check
      #   result exit status codes.
      # @yieldparam total_state_change [Float] percentage for the
      #   check history (exit status codes).
      # @yieldparam last_ok [Integer] execution timestamp of the last
      #   OK check result.
      def check_history(client, check)
        history_key = "history:#{client[:name]}:#{check[:name]}"
        @redis.lrange(history_key, -21, -1) do |history|
          total_state_change = 0
          unless history.length < 21
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
          @redis.get("#{history_key}:last_ok") do |last_ok|
            last_ok = last_ok.to_i unless last_ok.nil?
            yield(history, total_state_change, last_ok)
          end
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
          if check[:low_flap_threshold].is_a?(Integer) && check[:high_flap_threshold].is_a?(Integer)
            was_flapping = stored_event && stored_event[:action] == EVENT_FLAPPING_ACTION
            if was_flapping
              check[:total_state_change] > check[:low_flap_threshold]
            else
              check[:total_state_change] >= check[:high_flap_threshold]
            end
          else
            details = {:check => check}
            details[:client] = stored_event[:client] if stored_event
            @logger.error("invalid check flap thresholds", details)
            false
          end
        else
          false
        end
      end

      # Determine if an event has been silenced. This method compiles
      # an array of possible silenced registry entry keys for the
      # event. An attempt is made to fetch one or more of the silenced
      # registry entries to determine if the event has been silenced.
      # The event data is updated to indicate if the event has been
      # silenced. If the event is silenced and the event action is
      # `:resolve`, silenced registry entries with
      # `:expire_on_resolve` set to true will be deleted. Silencing is
      # disabled for events with a check status of `0` (OK), unless
      # the event action is `:resolve` or `:flapping`.
      #
      # @param event [Hash]
      # @yield callback [event] callback/block called after the event
      #   data has been updated to indicate if it has been silenced.
      def event_silenced?(event)
        event[:silenced] = false
        event[:silenced_by] = []
        if event[:check][:status] != 0 || event[:action] != :create
          check_name = event[:check][:name]
          silenced_keys = event[:client][:subscriptions].map { |subscription|
            ["silence:#{subscription}:*", "silence:#{subscription}:#{check_name}"]
          }.flatten
          silenced_keys << "silence:*:#{check_name}"
          @redis.mget(*silenced_keys) do |silenced|
            silenced.compact!
            silenced.each do |silenced_json|
              silenced_info = Sensu::JSON.load(silenced_json)
              if silenced_info[:expire_on_resolve] && event[:action] == :resolve
                silenced_key = "silence:#{silenced_info[:id]}"
                @redis.srem("silenced", silenced_key)
                @redis.del(silenced_key)
              elsif silenced_info[:begin].nil? || silenced_info[:begin] <= Time.now.to_i
                event[:silenced_by] << silenced_info[:id]
              end
            end
            event[:silenced] = !event[:silenced_by].empty?
            yield(event)
          end
        else
          yield(event)
        end
      end

      # Update the event registry, stored in Redis. This method
      # determines if event data warrants in the creation or update of
      # event data in the registry. If a check `:status` is not
      # `0`, or it has been flapping, an event is created/updated in
      # the registry. If the event `:action` is `:resolve`, the event
      # is removed (resolved) from the registry. If the previous
      # conditions are not met and check `:type` is `metric`, the
      # registry is not updated, but further event processing is
      # required (`yield(true)`). JSON serialization is used when
      # storing data in the registry.
      #
      # @param event [Hash]
      # @yield callback [event] callback/block called after the event
      #   registry has been updated.
      # @yieldparam process [TrueClass, FalseClass] indicating if the
      #   event requires further processing.
      def update_event_registry(event)
        client_name = event[:client][:name]
        if event[:check][:status] != 0 || (event[:action] == :flapping && event[:check][:force_resolve] != true)
          @redis.hset("events:#{client_name}", event[:check][:name], Sensu::JSON.dump(event)) do
            yield(true)
          end
        elsif event[:action] == :resolve &&
            (event[:check][:auto_resolve] != false || event[:check][:force_resolve]) ||
            (event[:action] == :flapping && event[:check][:force_resolve])
          @redis.hdel("events:#{client_name}", event[:check][:name]) do
            yield(true)
          end
        elsif event[:check][:type] == METRIC_CHECK_TYPE
          yield(true)
        else
          yield(false)
        end
      end

      # Create an event, using the provided client and check result
      # data. Existing event data for the client/check pair is fetched
      # from the event registry to be used in the composition of the
      # new event. The silenced registry is used to determine if the
      # event has been silenced.
      #
      # @param client [Hash]
      # @param check [Hash]
      # @yield callback [event] callback/block called with the
      #   resulting event.
      # @yieldparam event [Hash]
      def create_event(client, check)
        check_history(client, check) do |history, total_state_change, last_ok|
          check[:history] = history
          check[:total_state_change] = total_state_change
          @redis.hget("events:#{client[:name]}", check[:name]) do |event_json|
            stored_event = event_json ? Sensu::JSON.load(event_json) : nil
            flapping = check_flapping?(stored_event, check)
            event = {
              :id => random_uuid,
              :client => client,
              :check => check,
              :occurrences => 1,
              :occurrences_watermark => 1,
              :last_ok => last_ok,
              :action => (flapping ? :flapping : :create),
              :timestamp => Time.now.to_i
            }
            if stored_event
              event[:id] = stored_event[:id]
              event[:last_state_change] = stored_event[:last_state_change]
              event[:occurrences] = stored_event[:occurrences]
              event[:occurrences_watermark] = stored_event[:occurrences_watermark] || event[:occurrences]
            end
            if check[:status] != 0 || flapping
              if history[-1] == history[-2]
                event[:occurrences] += 1
                if event[:occurrences] > event[:occurrences_watermark]
                  event[:occurrences_watermark] = event[:occurrences]
                end
              else
                event[:occurrences] = 1
                event[:last_state_change] = event[:timestamp]
              end
            elsif stored_event
              event[:last_state_change] = event[:timestamp]
              event[:action] = :resolve
            end
            event_silenced?(event) do |event|
              yield(event)
            end
          end
        end
      end

      # Create a blank client (data). Only the client name is known,
      # the other client attributes must be updated via the API (POST
      # /clients:client). Dynamically created clients and those
      # updated via the API will have client keepalives disabled by
      # default, `:keepalives` is set to `false`.
      #
      # @param name [String] to use for the client.
      # @return [Hash] client.
      def create_client(name)
        {
          :name => name,
          :address => "unknown",
          :subscriptions => ["client:#{name}"],
          :keepalives => false,
          :version => VERSION,
          :timestamp => Time.now.to_i
        }
      end

      # Retrieve a client (data) from Redis if it exists. If a client
      # does not already exist, create one (a blank) using the
      # `client_key` as the client name. Dynamically create client
      # data can be updated using the API (POST /clients/:client). If
      # a client does exist and it has a client signature, the check
      # result must have a matching signature or it is discarded. If
      # the client does not exist, but a client signature exists, the
      # check result must have a matching signature or it is
      # discarded.
      #
      # @param result [Hash] data.
      # @yield [client] callback/block to be called with client data,
      #   either retrieved from Redis, or dynamically created.
      # @yieldparam client [Hash]
      def retrieve_client(result)
        client_key = result[:check][:source] || result[:client]
        @redis.get("client:#{client_key}") do |client_json|
          unless client_json.nil?
            client = Sensu::JSON.load(client_json)
            if client[:signature]
              if client[:signature] == result[:signature]
                yield(client)
              else
                @logger.warn("invalid check result signature", {
                  :result => result,
                  :client => client
                })
                @logger.warn("not retrieving client from the registry", :result => result)
                yield(nil)
              end
            else
              yield(client)
            end
          else
            @redis.get("client:#{client_key}:signature") do |signature|
              if signature.nil? || signature.empty? || result[:signature] == signature
                client = create_client(client_key)
                client[:type] = "proxy" if result[:check][:source]
                update_client_registry(client) do
                  yield(client)
                end
              else
                @logger.warn("invalid check result signature", {
                  :result => result,
                  :signature => signature
                })
                yield(nil)
              end
            end
          end
        end
      end

      # Determine if a keepalive event exists for a client.
      #
      # @param client_name [String] name of client to look up in event registry.
      # @return [TrueClass, FalseClass]
      def keepalive_event_exists?(client_name)
        @redis.hexists("events:#{client_name}", "keepalive") do |event_exists|
          yield(event_exists)
        end
      end

      # Process a check result, storing its data, inspecting its
      # contents, and taking the appropriate actions (eg. update the
      # event registry). The `@in_progress[:check_results]` counter is
      # incremented by `1` prior to check result processing and then
      # decremented by `1` after updating the event registry. A check
      # result must have a valid client name, associated with a client
      # in the registry or one will be created. If a local check
      # definition exists for the check name, and the check result is
      # not from a standalone check execution, it's merged with the
      # check result for more context.
      #
      # @param result [Hash] data.
      def process_check_result(result)
        @in_progress[:check_results] += 1
        @logger.debug("processing result", :result => result)
        retrieve_client(result) do |client|
          unless client.nil?
            check = case
            when @settings.check_exists?(result[:check][:name]) && !result[:check][:standalone]
              @settings[:checks][result[:check][:name]].merge(result[:check])
            else
              result[:check]
            end
            check[:type] ||= STANDARD_CHECK_TYPE
            check[:origin] = result[:client] if check[:source]
            if @settings.check_exists?(check[:name]) && client[:type] == "proxy"
              check[:command] = @settings[:checks][check[:name].to_sym][:command]
            end
            aggregate_check_result(client, check) if check[:aggregates] || check[:aggregate]
            store_check_result(client, check) do
              create_event(client, check) do |event|
                event_bridges(event)
                update_event_registry(event) do |process|
                  process_event(event) if process
                  @in_progress[:check_results] -= 1
                end
              end
            end
          else
            @logger.warn("halting result processing", :result => result)
            @in_progress[:check_results] -= 1
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
        results_pipe = "results"
        if @settings[:sensu][:server] && @settings[:sensu][:server][:results_pipe]
          results_pipe = @settings[:sensu][:server][:results_pipe]
        end
        @logger.debug("subscribing to results", :pipe => results_pipe)
        @transport.subscribe(:direct, results_pipe, "results", :ack => true) do |message_info, message|
          if message_size_ok?(message)
            begin
              result = Sensu::JSON.load(message)
              @logger.debug("received result", :result => result)
              process_check_result(result)
            rescue Sensu::JSON::ParseError => error
              @logger.error("failed to parse result payload", {
                :message => message,
                :error => error.to_s
              })
            end
          end
          EM::next_tick do
            @transport.ack(message_info)
          end
        end
      end

      # Determine the Sensu Transport publish options for a
      # subscription. If a subscription begins with a Transport pipe
      # type, either "direct:" or "roundrobin:", the subscription uses
      # a direct Transport pipe. If a subscription does not specify a
      # Transport pipe type, a fanout Transport pipe is used.
      #
      # @param subscription [String]
      # @param message [String]
      # @return [Array] containing the Transport publish options:
      #   the Transport pipe type, pipe, and the message to be
      #   published.
      def transport_publish_options(subscription, message)
        _, raw_type = subscription.split(":", 2).reverse
        case raw_type
        when "direct", "roundrobin"
          [:direct, subscription, message]
        else
          [:fanout, subscription, message]
        end
      end

      # Publish a check request to the Transport. A check request is
      # composed of a check definition (minus `:subscribers` and
      # `:interval`) and an `:issued` timestamp. The check request is
      # published to a Transport pipe, for each of the check
      # `:subscribers` in its definition, eg. "webserver". JSON
      # serialization is used when publishing the check request
      # payload to the Transport pipes. Transport errors are logged.
      #
      # @param check [Hash] definition.
      def publish_check_request(check)
        payload = check.reject do |key, value|
          [:subscribers, :interval].include?(key)
        end
        payload[:issued] = Time.now.to_i
        @logger.info("publishing check request", {
          :payload => payload,
          :subscribers => check[:subscribers]
        })
        check[:subscribers].each do |subscription|
          options = transport_publish_options(subscription, Sensu::JSON.dump(payload))
          @transport.publish(*options) do |info|
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

      # Determine and return clients from the registry that match a
      # set of attributes.
      #
      # @param clients [Array] of client names.
      # @param attributes [Hash]
      # @yield [Array] callback/block called after determining the
      #   matching clients, returning them as a block parameter.
      def determine_matching_clients(clients, attributes)
        client_keys = clients.map { |client_name| "client:#{client_name}" }
        @redis.mget(*client_keys) do |client_json_objects|
          matching_clients = []
          client_json_objects.each do |client_json|
            unless client_json.nil?
              client = Sensu::JSON.load(client_json)
              if attributes_match?(client, attributes)
                matching_clients << client
              end
            end
          end
          yield(matching_clients)
        end
      end

      # Publish a proxy check request for a client. This method
      # substitutes client tokens in the check definition prior to
      # publish the check request. If there are unmatched client
      # tokens, a warning is logged, and a check request is not
      # published.
      #
      # @param client [Hash] definition.
      # @param check [Hash] definition.
      def publish_proxy_check_request(client, check)
        @logger.debug("creating a proxy check request", {
          :client => client,
          :check => check
        })
        proxy_check, unmatched_tokens = object_substitute_tokens(deep_dup(check.dup), client)
        if unmatched_tokens.empty?
          proxy_check[:source] ||= client[:name]
          publish_check_request(proxy_check)
        else
          @logger.warn("failed to publish a proxy check request", {
            :reason => "unmatched client tokens",
            :unmatched_tokens => unmatched_tokens,
            :client => client,
            :check => check
          })
        end
      end

      # Publish proxy check requests for one or more clients. This
      # method can optionally splay proxy check requests, evenly, over
      # a period of time, determined by the check interval and a
      # configurable splay coverage percentage. For example, splay
      # proxy check requests over 60s * 90%, 54s, leaving 6s for the
      # last proxy check execution before the the next round of proxy
      # check requests for the same check. The
      # `publish_proxy_check_request() method is used to publish the
      # proxy check requests.
      #
      # @param clients [Array] of client definitions.
      # @param check [Hash] definition.
      def publish_proxy_check_requests(clients, check)
        client_count = clients.length
        splay = 0
        if check[:proxy_requests][:splay]
          interval = check[:interval]
          if check[:cron]
            interval = determine_check_cron_time(check)
          end
          unless interval.nil?
            splay_coverage = check[:proxy_requests].fetch(:splay_coverage, 90)
            splay = interval * (splay_coverage / 100.0) / client_count
          end
        end
        splay_timer = 0
        clients.each do |client|
          unless splay == 0
            EM::Timer.new(splay_timer) do
              publish_proxy_check_request(client, check)
            end
            splay_timer += splay
          else
            publish_proxy_check_request(client, check)
          end
        end
      end

      # Create and publish one or more proxy check requests. This
      # method iterates through the Sensu client registry for clients
      # that matched provided proxy request client attributes. A proxy
      # check request is created for each client in the registry that
      # matches the proxy request client attributes. Proxy check
      # requests have their client tokens subsituted by the associated
      # client attributes values. The `determine_matching_clients()`
      # method is used to fetch and inspect each slide of clients from
      # the registry, returning those that match the configured proxy
      # request client attributes. A relatively small clients slice
      # size (20) is used to reduce the number of clients inspected
      # within a single tick of the EM reactor. The
      # `publish_proxy_check_requests()` method is used to iterate
      # through the matching Sensu clients, creating their own unique
      # proxy check request, substituting client tokens, and then
      # publishing them to the targetted subscriptions.
      #
      # @param check [Hash] definition.
      def create_proxy_check_requests(check)
        client_attributes = check[:proxy_requests][:client_attributes]
        unless client_attributes.empty?
          @redis.smembers("clients") do |clients|
            client_count = clients.length
            proxy_check_requests = Proc.new do |matching_clients, slice_start, slice_size|
              unless slice_start > client_count - 1
                clients_slice = clients.slice(slice_start..slice_size)
                determine_matching_clients(clients_slice, client_attributes) do |additional_clients|
                  matching_clients += additional_clients
                  proxy_check_requests.call(matching_clients, slice_start + 20, slice_size + 20)
                end
              else
                publish_proxy_check_requests(matching_clients, check)
              end
            end
            proxy_check_requests.call([], 0, 19)
          end
        end
      end

      # Create a check request proc, used to publish check requests to
      # for a check to the Sensu transport. Check requests are not
      # published if subdued. This method determines if a check uses
      # proxy check requests and calls the appropriate check request
      # publish method.
      #
      # @param check [Hash] definition.
      def create_check_request_proc(check)
        Proc.new do
          unless check_subdued?(check)
            if check[:proxy_requests]
              create_proxy_check_requests(check)
            else
              publish_check_request(check)
            end
          else
            @logger.info("check request was subdued", :check => check)
          end
        end
      end

      # Schedule a check request, using the check cron. This method
      # determines the time until the next cron time (in seconds) and
      # creats an EventMachine timer for the request. This method will
      # be called after every check cron request for subsequent
      # requests. The timer is stored in the timer hash under
      # `:tasks`, so it can be cancelled etc. The check cron request
      # timer object is removed from the timer hash after the request
      # is published, to stop the timer hash from growing infinitely.
      #
      # @param check [Hash] definition.
      def schedule_check_cron_request(check)
        cron_time = determine_check_cron_time(check)
        @timers[:tasks][:check_request_publisher] << EM::Timer.new(cron_time) do |timer|
          create_check_request_proc(check).call
          @timers[:tasks][:check_request_publisher].delete(timer)
          schedule_check_cron_request(check)
        end
      end

      # Calculate a check request splay, taking into account the
      # current time and the request interval to ensure it's
      # consistent between process restarts.
      #
      # @param check [Hash] definition.
      def calculate_check_request_splay(check)
        splay_hash = Digest::MD5.digest(check[:name]).unpack('Q<').first
        current_time = (Time.now.to_f * 1000).to_i
        (splay_hash - current_time) % (check[:interval] * 1000) / 1000.0
      end

      # Schedule check requests, using the check interval. This method
      # using an intial calculated request splay EventMachine timer
      # and an EventMachine periodic timer for subsequent check
      # requests. The timers are stored in the timers hash under
      # `:tasks`, so they can be cancelled etc.
      #
      # @param check [Hash] definition.
      def schedule_check_interval_requests(check)
        request_splay = testing? ? 0 : calculate_check_request_splay(check)
        interval = testing? ? 0.5 : check[:interval]
        @timers[:tasks][:check_request_publisher] << EM::Timer.new(request_splay) do
          create_check_request = create_check_request_proc(check)
          create_check_request.call
          @timers[:tasks][:check_request_publisher] << EM::PeriodicTimer.new(interval, &create_check_request)
        end
      end

      # Schedule check requests. This method iterates through defined
      # checks and uses the appropriate method of check request
      # scheduling, either with the cron syntax or a numeric interval.
      #
      # @param checks [Array] of definitions.
      def schedule_checks(checks)
        checks.each do |check|
          if check[:cron]
            schedule_check_cron_request(check)
          else
            schedule_check_interval_requests(check)
          end
        end
      end

      # Set up the check request publisher. This method creates an
      # array of check definitions, that are not standalone checks,
      # and do not have `:publish` set to `false`. The array is
      # provided to the `schedule_checks()` method.
      def setup_check_request_publisher
        @logger.debug("scheduling check requests")
        checks = @settings.checks.reject do |check|
          check[:standalone] || check[:publish] == false
        end
        schedule_checks(checks)
      end

      # Publish a check result to the Transport for processing. A
      # check result is composed of a client name and a check
      # definition, containing check `:output` and `:status`. A client
      # signature is added to the check result payload if one is
      # registered for the client. JSON serialization is used when
      # publishing the check result payload to the Transport pipe.
      # Transport errors are logged.
      #
      # @param client_name [String]
      # @param check [Hash]
      def publish_check_result(client_name, check)
        payload = {
          :client => client_name,
          :check => check
        }
        @redis.get("client:#{client_name}:signature") do |signature|
          payload[:signature] = signature if signature
          @logger.debug("publishing check result", :payload => payload)
          @transport.publish(:direct, "results", Sensu::JSON.dump(payload)) do |info|
            if info[:error]
              @logger.error("failed to publish check result", {
                :payload => payload,
                :error => info[:error].to_s
              })
            end
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
      #
      # @return [Array] check definition, unmatched client tokens
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
        if @settings[:sensu][:keepalives]
          check = deep_merge(check, @settings[:sensu][:keepalives])
        end
        if client.has_key?(:keepalive)
          check = deep_merge(check, client[:keepalive])
        end
        timestamp = Time.now.to_i
        check.merge!(:name => "keepalive", :issued => timestamp, :executed => timestamp)
        object_substitute_tokens(check, client)
      end

      # Create client keepalive check results. This method will
      # retrieve clients from the registry, creating a keepalive
      # check definition for each client, using the
      # `create_keepalive_check()` method, containing client specific
      # keepalive thresholds. If the time since the latest keepalive
      # is equal to or greater than a threshold, the check `:output`
      # is set to a descriptive message, and `:status` is set to the
      # appropriate non-zero value. If a client has been sending
      # keepalives, `:output` and `:status` are set to indicate an OK
      # state. The `publish_check_result()` method is used to publish
      # the client keepalive check results.
      #
      # @param clients [Array] of client names.
      # @yield [] callback/block called after the client keepalive
      #   check results have been created.
      def create_client_keepalive_check_results(clients)
        client_keys = clients.map { |client_name| "client:#{client_name}" }
        @redis.mget(*client_keys) do |client_json_objects|
          client_json_objects.each do |client_json|
            unless client_json.nil?
              client = Sensu::JSON.load(client_json)
              next if client[:keepalives] == false
              check, unmatched_tokens = create_keepalive_check(client)
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
              unless unmatched_tokens.empty?
                check[:output] << " - Unmatched client token(s): " + unmatched_tokens.join(", ")
                check[:status] = 1 if check[:status] == 0
              end
              publish_check_result(client[:name], check)
            end
          end
          yield
        end
      end

      # Determine stale clients, those that have not sent a keepalive
      # in a specified amount of time. This method iterates through
      # the client registry, creating a keepalive check result for
      # each client. The `create_client_keepalive_check_results()`
      # method is used to inspect and create keepalive check results
      # for each slice of clients from the registry. A relatively
      # small clients slice size (20) is used to reduce the number of
      # clients inspected within a single tick of the EM reactor.
      def determine_stale_clients
        @logger.info("determining stale clients")
        @redis.smembers("clients") do |clients|
          client_count = clients.length
          keepalive_check_results = Proc.new do |slice_start, slice_size|
            unless slice_start > client_count - 1
              clients_slice = clients.slice(slice_start..slice_size)
              create_client_keepalive_check_results(clients_slice) do
                keepalive_check_results.call(slice_start + 20, slice_size + 20)
              end
            end
          end
          keepalive_check_results.call(0, 19)
        end
      end

      # Set up the client monitor, a periodic timer to run
      # `determine_stale_clients()` every 30 seconds. The timer is
      # stored in the timers hash under `:tasks`.
      def setup_client_monitor
        @logger.debug("monitoring client keepalives")
        @timers[:tasks][:client_monitor] << EM::PeriodicTimer.new(30) do
          determine_stale_clients
        end
      end

      # Create check TTL results. This method will retrieve check
      # results from the registry and determine the time since their
      # last check execution (in seconds). If the time since last
      # execution is equal to or greater than the defined check TTL, a
      # warning check result is published with the appropriate check
      # output.
      #
      # @param ttl_keys [Array] of TTL keys.
      # @param interval [Integer] to use for the check TTL result
      #   interval.
      # @yield [] callback/block called after the check TTL results
      #   have been created.
      def create_check_ttl_results(ttl_keys, interval=30)
        result_keys = ttl_keys.map { |ttl_key| "result:#{ttl_key}" }
        @redis.mget(*result_keys) do |result_json_objects|
          result_json_objects.each_with_index do |result_json, index|
            unless result_json.nil?
              check = Sensu::JSON.load(result_json)
              next unless check[:ttl] && check[:executed] && !check[:force_resolve]
              time_since_last_execution = Time.now.to_i - check[:executed]
              if time_since_last_execution >= check[:ttl]
                client_name = ttl_keys[index].split(":").first
                keepalive_event_exists?(client_name) do |event_exists|
                  unless event_exists
                    check[:output] = "Last check execution was "
                    check[:output] << "#{time_since_last_execution} seconds ago"
                    check[:status] = check[:ttl_status] || 1
                    check[:interval] = interval
                    publish_check_result(client_name, check)
                  end
                end
              end
            else
              @redis.srem("ttl", ttl_keys[index])
            end
          end
          yield
        end
      end

      # Determine stale check results, those that have not executed in
      # a specified amount of time (check TTL). This method iterates
      # through stored check results that have a defined TTL value (in
      # seconds). The `create_check_ttl_results()` method is used to
      # inspect each check result, calculating their time since last
      # check execution (in seconds). If the time since last execution
      # is equal to or greater than the check TTL, a warning check
      # result is published with the appropriate check output. A
      # relatively small check results slice size (20) is used to
      # reduce the number of check results inspected within a single
      # tick of the EM reactor.
      #
      # @param interval [Integer] to use for the check TTL result
      #   interval.
      def determine_stale_check_results(interval=30)
        @logger.info("determining stale check results (ttl)")
        @redis.smembers("ttl") do |ttl_keys|
          ttl_key_count = ttl_keys.length
          ttl_check_results = Proc.new do |slice_start, slice_size|
            unless slice_start > ttl_key_count - 1
              ttl_keys_slice = ttl_keys.slice(slice_start..slice_size)
              create_check_ttl_results(ttl_keys_slice, interval) do
                ttl_check_results.call(slice_start + 20, slice_size + 20)
              end
            end
          end
          ttl_check_results.call(0, 19)
        end
      end

      # Set up the check result monitor, a periodic timer to run
      # `determine_stale_check_results()` every 30 seconds. The timer
      # is stored in the timers hash under `:tasks`.
      #
      # @param interval [Integer] to use for the check TTL result
      #   interval.
      def setup_check_result_monitor(interval=30)
        @logger.debug("monitoring check results")
        @timers[:tasks][:check_result_monitor] << EM::PeriodicTimer.new(interval) do
          determine_stale_check_results(interval)
        end
      end

      # Create a lock timestamp (integer), current time including
      # milliseconds. This method is used by Sensu server task
      # election.
      #
      # @return [Integer]
      def create_lock_timestamp
        (Time.now.to_f * 10000000).to_i
      end

      # Create/return the unique Sensu server ID for the current
      # process.
      #
      # @return [String]
      def server_id
        @server_id ||= random_uuid
      end

      # Setup a Sensu server task. Unless the current process is
      # already responsible for the task, this method sets the tasks
      # server ID stored in Redis to the unique random server ID for
      # the process. If the tasks server ID is successfully updated,
      # the task is added to `@tasks` for tracking purposes and the
      # task setup method is called.
      #
      # @param task [String]
      # @yield callback/block called after setting up the task.
      def setup_task(task)
        unless @tasks.include?(task)
          @redis.set("task:#{task}:server", server_id) do
            @logger.info("i am now responsible for a server task", :task => task)
            @tasks << task
            self.send("setup_#{task}".to_sym)
            yield if block_given?
          end
        else
          @logger.debug("i am already responsible for a server task", :task => task)
        end
      end

      # Relinquish a Sensu server task. This method cancels and
      # clears the associated task timers, those with references
      # stored in the timers hash under `:tasks`, and removes the task
      # from `@tasks`. The task server ID and lock are not removed
      # from Redis, as they will be updated when another server takes
      # reponsibility for the task, this method does not need to
      # handle Redis connectivity issues.
      #
      # @param task [String]
      def relinquish_task(task)
        if @tasks.include?(task)
          @logger.warn("relinquishing server task", :task => task)
          @timers[:tasks][task.to_sym].each do |timer|
            timer.cancel
          end
          @timers[:tasks][task.to_sym].clear
          @tasks.delete(task)
        else
          @logger.debug("not currently responsible for a server task", :task => task)
        end
      end

      # Relinquish all Sensu server tasks, if any.
      def relinquish_tasks
        unless @tasks.empty?
          @tasks.dup.each do |task|
            relinquish_task(task)
          end
        else
          @logger.debug("not currently responsible for a server task")
        end
      end

      # Updates a Sensu server task lock timestamp. The current task
      # server ID is retrieved from Redis and compared with the server
      # ID of the current process to determine if it is still
      # responsible for the task. If the current process is still
      # responsible, the task lock timestamp is updated. If the
      # current process is no longer responsible, `relinquish_task()`
      # is called for cleanup.
      #
      # @param task [String]
      def update_task_lock(task)
        @redis.get("task:#{task}:server") do |current_server_id|
          if current_server_id == server_id
            @redis.set("lock:task:#{task}", create_lock_timestamp) do
              @logger.debug("updated task lock timestamp", :task => task)
            end
          else
            @logger.warn("another sensu server is responsible for the task", :task => task)
            relinquish_task(task)
          end
        end
      end

      # Set up a Sensu server task lock updater. This method uses a
      # periodic timer to update a task lock timestamp in Redis, every
      # 10 seconds. If the current process fails to keep the lock
      # timestamp updated for a task that it is responsible for,
      # another Sensu server will claim responsibility. This method is
      # called after task setup.
      #
      # @param task [String]
      def setup_task_lock_updater(task)
        @timers[:run] << EM::PeriodicTimer.new(10) do
          update_task_lock(task)
        end
      end

      # Request a Sensu server task election, a process to determine
      # if the current process is to be responsible for the task. A
      # Redis key/value is used as a central lock, using the "SETNX"
      # Redis command to set the key/value if it does not exist, using
      # a timestamp for the value. If the current process was able to
      # create the key/value, it is elected, and is then responsible
      # for the task. If the current process was not able to create
      # the key/value, but the current timestamp value is equal to or
      # over 30 seconds ago, the "GETSET" Redis command is used to set
      # a new timestamp and fetch the previous value to compare them,
      # to determine if it was set by the current process. If the
      # current process is able to set the timestamp value, it is
      # elected. If elected, the current process sets up the task and
      # the associated task lock updater.
      #
      # @param task [String]
      # @yield callback/block called either after being elected and
      #   setting up the task, or after failing to be elected.
      def request_task_election(task, &callback)
        @redis.setnx("lock:task:#{task}", create_lock_timestamp) do |created|
          if created
            setup_task(task, &callback)
            setup_task_lock_updater(task)
          else
            @redis.get("lock:task:#{task}") do |current_lock_timestamp|
              new_lock_timestamp = create_lock_timestamp
              if new_lock_timestamp - current_lock_timestamp.to_i >= 300000000
                @redis.getset("lock:task:#{task}", new_lock_timestamp) do |previous_lock_timestamp|
                  if previous_lock_timestamp == current_lock_timestamp
                    setup_task(task, &callback)
                    setup_task_lock_updater(task)
                  end
                end
              else
                yield if block_given?
              end
            end
          end
        end
      end

      # Request Sensu server task elections. The task list is ordered
      # by prioity. This method works through the task list serially,
      # increasing the election request delay as the current process
      # becomes responsible for one or more tasks, this is to improve
      # the initial distribution of tasks amongst Sensu servers.
      #
      # @param splay [Integer]
      def setup_task_elections(splay=10)
        tasks = TASKS.dup - @tasks
        next_task = Proc.new do
          task = tasks.shift
          if task
            delay = splay * @tasks.size
            @timers[:run] << EM::Timer.new(delay) do
              request_task_election(task, &next_task)
            end
          else
            @timers[:run] << EM::Timer.new(10) do
              setup_task_elections(splay)
            end
          end
        end
        next_task.call
      end

      # Update the Sensu server registry, stored in Redis. This method
      # adds the local/current Sensu server info to the registry,
      # including its id, hostname, address, its server tasks, and
      # some metrics. Sensu server registry entries expire in 30
      # seconds unless updated.
      #
      # @yield [success] passes success status to optional
      #   callback/block.
      # @yieldparam success [TrueClass,FalseClass] indicating if the
      #   server registry update was a success.
      def update_server_registry
        @logger.debug("updating the server registry")
        process_cpu_times do |cpu_user, cpu_system, _, _|
          sensu = RELEASE_INFO.merge(
            :settings => {
              :hexdigest => @settings.hexdigest
            }
          )
          tessen = @settings[:tessen] || {}
          tessen_enabled = tessen.fetch(:enabled, false)
          info = {
            :id => server_id,
            :hostname => system_hostname,
            :address => system_address,
            :tasks => @tasks,
            :metrics => {
              :cpu => {
                :user => cpu_user,
                :system => cpu_system
              }
            },
            :sensu => sensu,
            :tessen => {
              :enabled => tessen_enabled
            },
            :timestamp => Time.now.to_i
          }
          @redis.sadd("servers", server_id)
          server_key = "server:#{server_id}"
          @redis.set(server_key, Sensu::JSON.dump(info)) do
            @redis.expire(server_key, 30)
            @logger.info("updated server registry", :server => info)
            yield(true) if block_given?
          end
        end
      end

      # Set up the server registry updater. A periodic timer is
      # used to update the Sensu server info stored in Redis. The
      # timer is stored in the timers hash under `:run`.
      def setup_server_registry_updater
        update_server_registry
        @timers[:run] << EM::PeriodicTimer.new(10) do
          update_server_registry
        end
      end

      # Set up Tessen, the call home mechanism.
      def setup_tessen
        @tessen = Tessen.new(
          :settings => @settings,
          :logger => @logger,
          :redis => @redis
        )
        @tessen.run if @tessen.enabled?
      end

      # Unsubscribe from transport subscriptions (all of them). This
      # method is called when there are issues with connectivity, or
      # the process is stopping.
      def unsubscribe
        @logger.warn("unsubscribing from keepalive and result queues")
        @transport.unsubscribe if @transport
      end

      # Complete in progress work and then call the provided callback.
      # This method will wait until all counters stored in the
      # `@in_progress` hash equal `0`.
      #
      # @yield [] callback/block to call when in progress work is
      #   completed.
      def complete_in_progress
        @logger.info("completing work in progress", :in_progress => @in_progress)
        retry_until_true do
          if @in_progress.values.all? { |count| count == 0 }
            yield
            true
          end
        end
      end

      # Bootstrap the Sensu server process, setting up the keepalive
      # and check result consumers, and attemping to carry out Sensu
      # server tasks. This method sets the process/daemon `@state` to
      # `:running`.
      def bootstrap
        setup_keepalives
        setup_results
        setup_task_elections
        setup_server_registry_updater
        setup_tessen
        @state = :running
      end

      # Start the Sensu server process, connecting to Redis, the
      # Transport, and calling the `bootstrap()` method. Yield if a
      # block is provided.
      def start
        setup_connections do
          bootstrap
          yield if block_given?
        end
      end

      # Pause the Sensu server process, unless it is being paused or
      # has already been paused. The process/daemon `@state` is first
      # set to `:pausing`, to indicate that it's in progress. All run
      # timers are cancelled, their references are cleared, and Tessen
      # is stopped. The Sensu server will unsubscribe from all
      # transport subscriptions, relinquish any Sensu server tasks,
      # then set the process/daemon `@state` to `:paused`.
      def pause
        unless @state == :pausing || @state == :paused
          @state = :pausing
          @timers[:run].each do |timer|
            timer.cancel
          end
          @timers[:run].clear
          @tessen.stop if @tessen
          unsubscribe
          relinquish_tasks
          @state = :paused
        end
      end

      # Resume the Sensu server process if it is currently or will
      # soon be paused. The `retry_until_true` helper method is used
      # to determine if the process is paused and if the Redis and
      # transport connections are initiated and connected. If the
      # conditions are met, `bootstrap()` will be called and true is
      # returned to stop `retry_until_true`. If the transport has not
      # yet been initiated, true is is returned, without calling
      # bootstrap, as we expect bootstrap will be called after the
      # transport initializes.
      def resume
        retry_until_true(1) do
          if @state == :paused
            if @redis.connected?
              if @transport
                if @transport.connected?
                  bootstrap
                  true
                end
              else
                true
              end
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
        complete_in_progress do
          @redis.close if @redis
          @transport.close if @transport
          super
        end
      end
    end
  end
end
