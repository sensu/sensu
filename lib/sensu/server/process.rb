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

      attr_reader :is_leader, :in_progress

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

      # Override Daemon initialize() to support Sensu server leader
      # election and the handling event count.
      #
      # @param options [Hash]
      def initialize(options={})
        super
        @is_leader = false
        @timers[:leader] = Array.new
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
      # enable agent health monitoring. The client registry supports
      # client signatures, unique string identifiers used for
      # keepalive and result source verification. If a client has a
      # signature, all further registry updates for the client must
      # have the same signature. A client can begin to use a signature
      # if one was not previously configured. JSON serialization is
      # used for the stored client data.
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
        signature_key = "#{client_key}:signature"
        @redis.setnx(signature_key, client[:signature]) do |created|
          process_client_registration(client) if created
          @redis.get(signature_key) do |signature|
            if (signature.nil? || signature.empty?) && client[:signature]
              @redis.set(signature_key, client[:signature])
            end
            if signature.nil? || signature.empty? || (client[:signature] == signature)
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
            client = Sensu::JSON.load(message)
            update_client_registry(client) do
              @transport.ack(message_info)
            end
          rescue Sensu::JSON::ParseError => error
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
              handle_event(handler, event_data)
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

      # Truncate check output. For metric checks, (`"type":
      # "metric"`), check output is truncated to a single line and a
      # maximum of 255 characters. Check output is currently left
      # unmodified for standard checks.
      #
      # @param check [Hash]
      # @return [Hash] check with truncated output.
      def truncate_check_output(check)
        case check[:type]
        when METRIC_CHECK_TYPE
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
          if output_lines.length > 1 || output.length > 255
            output = output[0..255] + "\n..."
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
          yield(history, total_state_change)
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
          was_flapping = stored_event && stored_event[:action] == EVENT_FLAPPING_ACTION
          if was_flapping
            check[:total_state_change] > check[:low_flap_threshold]
          else
            check[:total_state_change] >= check[:high_flap_threshold]
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
              else
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
        if event[:check][:status] != 0 || event[:action] == :flapping
          @redis.hset("events:#{client_name}", event[:check][:name], Sensu::JSON.dump(event)) do
            yield(true)
          end
        elsif event[:action] == :resolve &&
            (event[:check][:auto_resolve] != false || event[:check][:force_resolve])
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
        check_history(client, check) do |history, total_state_change|
          check[:history] = history
          check[:total_state_change] = total_state_change
          @redis.hget("events:#{client[:name]}", check[:name]) do |event_json|
            stored_event = event_json ? Sensu::JSON.load(event_json) : nil
            flapping = check_flapping?(stored_event, check)
            event = {
              :client => client,
              :check => check,
              :occurrences => 1,
              :occurrences_watermark => 1,
              :action => (flapping ? :flapping : :create),
              :timestamp => Time.now.to_i
            }
            if stored_event
              event[:id] = stored_event[:id]
              event[:last_state_change] = stored_event[:last_state_change]
              event[:last_ok] = stored_event[:last_ok]
              event[:occurrences] = stored_event[:occurrences]
              event[:occurrences_watermark] = stored_event[:occurrences_watermark] || event[:occurrences]
            else
              event[:id] = random_uuid
              event[:last_ok] = event[:timestamp]
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
            if check[:status] == 0
              event[:last_ok] = event[:timestamp]
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
          :version => VERSION
        }
      end

      # Retrieve a client (data) from Redis if it exists. If a client
      # does not already exist, create one (a blank) using the
      # `client_key` as the client name. Dynamically create client
      # data can be updated using the API (POST /clients/:client). If
      # a client does exist and it has a client signature, the check
      # result must have a matching signature or it is discarded.
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
            client = create_client(client_key)
            client[:type] = "proxy" if result[:check][:source]
            update_client_registry(client) do
              yield(client)
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
        @logger.debug("subscribing to results")
        @transport.subscribe(:direct, "results", "results", :ack => true) do |message_info, message|
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
      # the timers hash under `:leader`, as check request publishing
      # is a task for only the Sensu server leader, so they can be
      # cancelled etc. Check requests are not published if subdued.
      #
      # @param checks [Array] of definitions.
      def schedule_check_executions(checks)
        checks.each do |check|
          create_check_request = Proc.new do
            unless check_subdued?(check)
              publish_check_request(check)
            else
              @logger.info("check request was subdued", :check => check)
            end
          end
          execution_splay = testing? ? 0 : calculate_check_execution_splay(check)
          interval = testing? ? 0.5 : check[:interval]
          @timers[:leader] << EM::Timer.new(execution_splay) do
            create_check_request.call
            @timers[:leader] << EM::PeriodicTimer.new(interval, &create_check_request)
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
      # stored in the timers hash under `:leader`.
      def setup_client_monitor
        @logger.debug("monitoring client keepalives")
        @timers[:leader] << EM::PeriodicTimer.new(30) do
          determine_stale_clients
        end
      end

      # Determine stale check results, those that have not executed in
      # a specified amount of time (check TTL). This method iterates
      # through stored check results that have a defined TTL value (in
      # seconds). The time since last check execution (in seconds) is
      # calculated for each check result. If the time since last
      # execution is equal to or greater than the check TTL, a warning
      # check result is published with the appropriate check output.
      def determine_stale_check_results(interval = 30)
        @logger.info("determining stale check results")
        @redis.smembers("ttl") do |result_keys|
          result_keys.each do |result_key|
            @redis.get("result:#{result_key}") do |result_json|
              unless result_json.nil?
                check = Sensu::JSON.load(result_json)
                next unless check[:ttl] && check[:executed] && !check[:force_resolve]
                time_since_last_execution = Time.now.to_i - check[:executed]
                if time_since_last_execution >= check[:ttl]
                  client_name = result_key.split(":").first
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
                @redis.srem("ttl", result_key)
              end
            end
          end
        end
      end

      # Set up the check result monitor, a periodic timer to run
      # `determine_stale_check_results()` every 30 seconds. The timer
      # is stored in the timers hash under `:leader`.
      def setup_check_result_monitor(interval = 30)
        @logger.debug("monitoring check results")
        @timers[:leader] << EM::PeriodicTimer.new(interval) do
          determine_stale_check_results(interval)
        end
      end

      # Set up the leader duties, tasks only performed by a single
      # Sensu server at a time. The duties include publishing check
      # requests, monitoring for stale clients, and pruning check
      # result aggregations.
      def leader_duties
        setup_check_request_publisher
        setup_client_monitor
        setup_check_result_monitor
      end

      # Create a lock timestamp (integer), current time including
      # milliseconds. This method is used by Sensu server leader
      # election.
      #
      # @return [Integer]
      def create_lock_timestamp
        (Time.now.to_f * 1000).to_i
      end

      # Create/return the unique Sensu server leader ID for the
      # current process.
      #
      # @return [String]
      def leader_id
        @leader_id ||= random_uuid
      end

      # Become the Sensu server leader, responsible for specific
      # duties (`leader_duties()`). Unless the current process is
      # already the leader, this method sets the leader ID stored in
      # Redis to the unique random leader ID for the process. If the
      # leader ID in Redis is successfully updated, `@is_leader` is
      # set to true and `leader_duties()` is called to begin the
      # tasks/duties of the Sensu server leader.
      def become_the_leader
        unless @is_leader
          @redis.set("leader", leader_id) do
            @logger.info("i am now the leader")
            @is_leader = true
            leader_duties
          end
        else
          @logger.debug("i am already the leader")
        end
      end

      # Resign as leader, if the current process is the Sensu server
      # leader. This method cancels and clears the leader timers,
      # those with references stored in the timers hash under
      # `:leader`, and `@is_leader` is set to `false`. The leader ID
      # and leader lock are not removed from Redis, as they will be
      # updated when another server is elected to be the leader, this
      # method does not need to handle Redis connectivity issues.
      def resign_as_leader
        if @is_leader
          @logger.warn("resigning as leader")
          @timers[:leader].each do |timer|
            timer.cancel
          end
          @timers[:leader].clear
          @is_leader = false
        else
          @logger.debug("not currently the leader")
        end
      end

      # Updates the Sensu server leader lock timestamp. The current
      # leader ID is retrieved from Redis and compared with the leader
      # ID of the current process to determine if it is still the
      # Sensu server leader. If the current process is still the
      # leader, the leader lock timestamp is updated. If the current
      # process is no longer the leader (regicide),
      # `resign_as_leader()` is called for cleanup, so there is not
      # more than one leader.
      def update_leader_lock
        @redis.get("leader") do |current_leader_id|
          if current_leader_id == leader_id
            @redis.set("lock:leader", create_lock_timestamp) do
              @logger.debug("updated leader lock timestamp")
            end
          else
            @logger.warn("another sensu server has been elected as leader")
            resign_as_leader
          end
        end
      end

      # Request a leader election, a process to determine if the
      # current process is the Sensu server leader, with its
      # own/unique duties. A Redis key/value is used as a central
      # lock, using the "SETNX" Redis command to set the key/value if
      # it does not exist, using a timestamp for the value. If the
      # current process was able to create the key/value, it is the
      # leader, and must do the duties of the leader. If the current
      # process was not able to create the key/value, but the current
      # timestamp value is equal to or over 30 seconds ago, the
      # "GETSET" Redis command is used to set a new timestamp and
      # fetch the previous value to compare them, to determine if it
      # was set by the current process. If the current process is able
      # to set the timestamp value, it becomes the leader.
      def request_leader_election
        @redis.setnx("lock:leader", create_lock_timestamp) do |created|
          if created
            become_the_leader
          else
            @redis.get("lock:leader") do |current_lock_timestamp|
              new_lock_timestamp = create_lock_timestamp
              if new_lock_timestamp - current_lock_timestamp.to_i >= 30000
                @redis.getset("lock:leader", new_lock_timestamp) do |previous_lock_timestamp|
                  if previous_lock_timestamp == current_lock_timestamp
                    become_the_leader
                  end
                end
              end
            end
          end
        end
      end

      # Set up the leader monitor. A one-time timer is used to run
      # `request_leader_exection()` in 2 seconds. A periodic timer is
      # used to update the leader lock timestamp if the current
      # process is the leader, or to run `request_leader_election(),
      # every 10 seconds. The timers are stored in the timers hash
      # under `:run`.
      def setup_leader_monitor
        @timers[:run] << EM::Timer.new(2) do
          request_leader_election
        end
        @timers[:run] << EM::PeriodicTimer.new(10) do
          if @is_leader
            update_leader_lock
          else
            request_leader_election
          end
        end
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
      # and check result consumers, and attemping to become the leader
      # to carry out its duties. This method sets the process/daemon
      # `@state` to `:running`.
      def bootstrap
        setup_keepalives
        setup_results
        setup_leader_monitor
        @state = :running
      end

      # Start the Sensu server process, connecting to Redis, the
      # Transport, and calling the `bootstrap()` method.
      def start
        setup_connections do
          bootstrap
        end
      end

      # Pause the Sensu server process, unless it is being paused or
      # has already been paused. The process/daemon `@state` is first
      # set to `:pausing`, to indicate that it's in progress. All run
      # timers are cancelled, and the references are cleared. The
      # Sensu server will unsubscribe from all transport
      # subscriptions, resign as leader (if currently the leader),
      # then set the process/daemon `@state` to `:paused`.
      def pause
        unless @state == :pausing || @state == :paused
          @state = :pausing
          @timers[:run].each do |timer|
            timer.cancel
          end
          @timers[:run].clear
          unsubscribe
          resign_as_leader
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
