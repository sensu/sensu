require "sensu/daemon"
require "sensu/client/socket"

module Sensu
  module Client
    class Process
      include Daemon

      attr_accessor :safe_mode

      # Create an instance of the Sensu client process, start the
      # client within the EventMachine event loop, and set up client
      # process signal traps (for stopping).
      #
      # @param options [Hash]
      def self.run(options={})
        client = self.new(options)
        EM::run do
          client.start
          client.setup_signal_traps
        end
      end

      # Override Daemon initialize() to support Sensu client check
      # execution safe mode and checks in progress.
      #
      # @param options [Hash]
      def initialize(options={})
        super
        @safe_mode = @settings[:client][:safe_mode] || false
        @checks_in_progress = []
      end

      # Create a Sensu client keepalive payload, to be sent over the
      # transport for processing. A client keepalive is composed of
      # its settings definition, the Sensu version, and a timestamp.
      # Sensitive information is redacted from the keepalive payload.
      #
      # @return [Hash] keepalive payload
      def keepalive_payload
        payload = @settings[:client].merge({
          :version => VERSION,
          :timestamp => Time.now.to_i
        })
        redact_sensitive(payload, @settings[:client][:redact])
      end

      # Publish a Sensu client keepalive to the transport for
      # processing. JSON serialization is used for transport messages.
      def publish_keepalive
        payload = keepalive_payload
        @logger.debug("publishing keepalive", :payload => payload)
        @transport.publish(:direct, "keepalives", MultiJson.dump(payload)) do |info|
          if info[:error]
            @logger.error("failed to publish keepalive", {
              :payload => payload,
              :error => info[:error].to_s
            })
          end
        end
      end

      # Schedule Sensu client keepalives. Immediately publish a
      # keepalive to register the client, then publish a keepalive
      # every 20 seconds. Sensu client keepalives are used to
      # determine client (& machine) health.
      def setup_keepalives
        @logger.debug("scheduling keepalives")
        publish_keepalive
        @timers[:run] << EM::PeriodicTimer.new(20) do
          publish_keepalive
        end
      end

      # Publish a check result to the transport for processing. A
      # check result is composed of a client (name) and a check
      # definition, containing check `:output` and `:status`. JSON
      # serialization is used when publishing the check result payload
      # to the transport pipe. Transport errors are logged.
      #
      # @param check [Hash]
      def publish_check_result(check)
        payload = {
          :client => @settings[:client][:name],
          :check => check
        }
        @logger.info("publishing check result", :payload => payload)
        @transport.publish(:direct, "results", MultiJson.dump(payload)) do |info|
          if info[:error]
            @logger.error("failed to publish check result", {
              :payload => payload,
              :error => info[:error].to_s
            })
          end
        end
      end

      # Traverse the Sensu client definition (hash) for an attribute
      # value, with a fallback default value if nil.
      #
      # @param tree [Hash] to traverse.
      # @param path [Array] of attribute keys.
      # @param default [Object] value if attribute value is nil.
      # @return [Object] attribute or fallback default value.
      def find_client_attribute(tree, path, default)
        attribute = tree[path.shift]
        if attribute.is_a?(Hash)
          find_client_attribute(attribute, path, default)
        else
          attribute.nil? ? default : attribute
        end
      end

      # Substitue check command tokens (eg. :::db.name|production:::)
      # with the associated client definition attribute value. Command
      # tokens can provide a fallback default value, following a pipe.
      #
      # @param check [Hash]
      # @return [Array] containing the check command string with
      #   tokens substituted and an array of unmatched command tokens.
      def substitute_check_command_tokens(check)
        unmatched_tokens = []
        substituted = check[:command].gsub(/:::([^:].*?):::/) do
          token, default = $1.to_s.split("|", -1)
          matched = find_client_attribute(@settings[:client], token.split("."), default)
          if matched.nil?
            unmatched_tokens << token
          end
          matched
        end
        [substituted, unmatched_tokens]
      end

      # Execute a check command, capturing its output (STDOUT/ERR),
      # exit status code, execution duration, timestamp, and publish
      # the result. This method guards against multiple executions for
      # the same check. Check command tokens are substituted with the
      # associated client attribute values. If there are unmatched
      # check command tokens, the check command will not be executed,
      # instead a check result will be published reporting the
      # unmatched tokens.
      #
      # @param check [Hash]
      def execute_check_command(check)
        @logger.debug("attempting to execute check command", :check => check)
        unless @checks_in_progress.include?(check[:name])
          @checks_in_progress << check[:name]
          command, unmatched_tokens = substitute_check_command_tokens(check)
          if unmatched_tokens.empty?
            check[:executed] = Time.now.to_i
            started = Time.now.to_f
            Spawn.process(command, :timeout => check[:timeout]) do |output, status|
              check[:duration] = ("%.3f" % (Time.now.to_f - started)).to_f
              check[:output] = output
              check[:status] = status
              publish_check_result(check)
              @checks_in_progress.delete(check[:name])
            end
          else
            check[:output] = "Unmatched command tokens: " + unmatched_tokens.join(", ")
            check[:status] = 3
            check[:handle] = false
            publish_check_result(check)
            @checks_in_progress.delete(check[:name])
          end
        else
          @logger.warn("previous check command execution in progress", :check => check)
        end
      end

      # Run a check extension and publish the result. The Sensu client
      # loads check extensions, checks that run within the Sensu Ruby
      # VM and the EventMachine event loop, using the Sensu Extension
      # API.
      #
      # https://github.com/sensu/sensu-extension
      #
      # @param check [Hash]
      def run_check_extension(check)
        @logger.debug("attempting to run check extension", :check => check)
        check[:executed] = Time.now.to_i
        extension = @extensions[:checks][check[:name]]
        extension.safe_run do |output, status|
          check[:output] = output
          check[:status] = status
          publish_check_result(check)
        end
      end

      # Process a check request. If a check request has a check
      # command, it will be executed. A check request without a check
      # command indicates a check extension run. A check request will
      # be merged with a local check definition, if present. Client
      # safe mode is enforced in this method, requiring a local check
      # definition in order to execute the check command. If a local
      # check definition does not exist when operating with client
      # safe mode, a check result will be published to report the
      # missing check definition.
      #
      # @param check [Hash]
      def process_check_request(check)
        @logger.debug("processing check", :check => check)
        if check.has_key?(:command)
          if @settings.check_exists?(check[:name])
            check.merge!(@settings[:checks][check[:name]])
            execute_check_command(check)
          elsif @safe_mode
            check[:output] = "Check is not locally defined (safe mode)"
            check[:status] = 3
            check[:handle] = false
            check[:executed] = Time.now.to_i
            publish_check_result(check)
          else
            execute_check_command(check)
          end
        else
          if @extensions.check_exists?(check[:name])
            run_check_extension(check)
          else
            @logger.warn("unknown check extension", :check => check)
          end
        end
      end

      # Set up Sensu client subscriptions. Subscriptions determine the
      # kinds of check requests the client will receive. A unique
      # transport funnel is created for the Sensu client, using a
      # combination of it's name, the Sensu version, and the current
      # timestamp (epoch). The unique funnel is bound to each
      # transport pipe, named after the client subscription. The Sensu
      # client will receive JSON serialized check requests from its
      # funnel, that get parsed and processed.
      def setup_subscriptions_type(list, transport)
        list.each do |subscription|
          # Temporary fix - if transport is direct then prefix direct on the front of the subscription
          # to avoid collisions but allow backward compat with earlier sensu clients
          subscription = "direct_#{subscription}" if transport == :direct
          @logger.debug("subscribing to a subscription",
            :transport => transport, :subscription => subscription)
          funnel = [@settings[:client][:name], VERSION, Time.now.to_i].join("-")
          @transport.subscribe(transport, subscription, funnel) do |message_info, message|
            begin
              check = MultiJson.load(message)
              @logger.info("received check request", :check => check)
              process_check_request(check)
            rescue MultiJson::ParseError => error
              @logger.error("failed to parse the check request payload", {
                :message => message,
                :error => error.to_s
              })
            end
          end
        end
      end

      def setup_subscriptions
        @logger.debug('subscribing to client subscriptions')
        setup_subscriptions_type(@settings[:client].fetch(:subscriptions, []), :fanout)
        @logger.debug('subscribing to client floating subscriptions')
        setup_subscriptions_type(@settings[:client].fetch(:floating, []), :direct)
      end

      # Calculate a check execution splay, taking into account the
      # current time and the execution interval to ensure it's
      # consistent between process restarts.
      #
      # @param check [Hash] definition.
      def calculate_execution_splay(check)
        key = [@settings[:client][:name], check[:name]].join(":")
        splay_hash = Digest::MD5.digest(key).unpack("Q<").first
        current_time = (Time.now.to_f * 1000).to_i
        (splay_hash - current_time) % (check[:interval] * 1000) / 1000.0
      end

      # Schedule check executions, using EventMachine periodic timers,
      # using a calculated execution splay. The timers are stored in
      # the timers hash under `:run`, so they can be cancelled etc.
      # Check definitions are duplicated before processing them, in
      # case they are mutated. The check `:issued` timestamp is set
      # here, to mimic check requests issued by a Sensu server.
      #
      # @param checks [Array] of definitions.
      def schedule_checks(checks)
        checks.each do |check|
          execute_check = Proc.new do
            check[:issued] = Time.now.to_i
            process_check_request(check.dup)
          end
          execution_splay = testing? ? 0 : calculate_execution_splay(check)
          interval = testing? ? 0.5 : check[:interval]
          @timers[:run] << EM::Timer.new(execution_splay) do
            execute_check.call
            @timers[:run] << EM::PeriodicTimer.new(interval, &execute_check)
          end
        end
      end

      # Setup standalone check executions, scheduling standard check
      # definition and check extension executions. Check definitions
      # and extensions with `:standalone` set to `true` will be
      # scheduled by the Sensu client for execution.
      def setup_standalone
        @logger.debug("scheduling standalone checks")
        standard_checks = @settings.checks.select do |check|
          check[:standalone]
        end
        extension_checks = @extensions.checks.select do |check|
          check[:standalone] && check[:interval].is_a?(Integer)
        end
        schedule_checks(standard_checks + extension_checks)
      end

      # Setup the Sensu client socket, for external check result
      # input. By default, the client socket is bound to localhost on
      # TCP & UDP port 3030. The socket can be configured via the
      # client definition, `:socket` with `:bind` and `:port`. The
      # current instance of the Sensu logger, settings, and transport
      # are passed to the socket handler, `Sensu::Client::Socket`.
      def setup_sockets
        options = @settings[:client][:socket] || Hash.new
        options[:bind] ||= "127.0.0.1"
        options[:port] ||= 3030
        @logger.debug("binding client tcp and udp sockets", :options => options)
        EM::start_server(options[:bind], options[:port], Socket) do |socket|
          socket.logger = @logger
          socket.settings = @settings
          socket.transport = @transport
        end
        EM::open_datagram_socket(options[:bind], options[:port], Socket) do |socket|
          socket.logger = @logger
          socket.settings = @settings
          socket.transport = @transport
          socket.protocol = :udp
        end
      end

      # Call a callback (Ruby block) when there are no longer check
      # executions in progress. This method is used when stopping the
      # Sensu client. The `retry_until_true` helper method is used to
      # check the condition every 0.5 seconds until `true` is
      # returned.
      #
      # @param callback [Proc] called when there are no check
      #   executions in progress.
      def complete_checks_in_progress(&callback)
        @logger.info("completing checks in progress", :checks_in_progress => @checks_in_progress)
        retry_until_true do
          if @checks_in_progress.empty?
            callback.call
            true
          end
        end
      end

      # Bootstrap the Sensu client, setting up client keepalives,
      # subscriptions, and standalone check executions. This method
      # sets the process/daemon `@state` to `:running`.
      def bootstrap
        setup_keepalives
        setup_subscriptions
        setup_standalone
        @state = :running
      end

      # Start the Sensu client process, setting up the client
      # transport connection, the sockets, and calling the
      # `bootstrap()` method.
      def start
        setup_transport
        setup_sockets
        bootstrap
      end

      # Pause the Sensu client process, unless it is being paused or
      # has already been paused. The process/daemon `@state` is first
      # set to `:pausing`, to indicate that it's in progress. All run
      # timers are cancelled, and the references are cleared. The
      # Sensu client will unsubscribe from all transport
      # subscriptions, then set the process/daemon `@state` to
      # `:paused`.
      def pause
        unless @state == :pausing || @state == :paused
          @state = :pausing
          @timers[:run].each do |timer|
            timer.cancel
          end
          @timers[:run].clear
          @transport.unsubscribe
          @state = :paused
        end
      end

      # Resume the Sensu client process if it is currently or will
      # soon be paused. The `retry_until_true` helper method is used
      # to determine if the process is paused and if the transport is
      # connected. If the conditions are met, `bootstrap()` will be
      # called and true is returned to stop `retry_until_true`.
      def resume
        retry_until_true(1) do
          if @state == :paused
            if @transport.connected?
              bootstrap
              true
            end
          end
        end
      end

      # Stop the Sensu client process, pausing it, completing check
      # executions in progress, closing the transport connection, and
      # exiting the process (exit 0). After pausing the process, the
      # process/daemon `@state` is set to `:stopping`.
      def stop
        @logger.warn("stopping")
        pause
        @state = :stopping
        complete_checks_in_progress do
          @transport.close
          super
        end
      end
    end
  end
end
