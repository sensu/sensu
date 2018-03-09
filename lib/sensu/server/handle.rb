require "sensu/server/socket"

module Sensu
  module Server
    module Handle
      # Create a handler error callback, for logging the error and
      # decrementing the `@in_progress[:events]` by `1`.
      #
      # @param handler [Object]
      # @param event_data [Object]
      # @param event_id [String] event UUID
      # @return [Proc] error callback.
      def handler_error(handler, event_data, event_id)
        Proc.new do |error|
          @logger.error("handler error", {
            :handler => handler,
            :event => {
              :id => event_id
            },
            :event_data => event_data,
            :error => error.to_s
          })
          @in_progress[:events] -= 1 if @in_progress
        end
      end

      # Execute a pipe event handler, using the defined handler
      # command to spawn a process, passing it event data via STDIN.
      # Log the handler output lines and decrement the
      # `@in_progress[:events]` by `1` when the handler executes
      # successfully.
      #
      # When the spawned process exits with status 0, its output is
      # logged at :info level. Otherwise, its output is logged at
      # :error level.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] provided to the spawned handler
      #   process via STDIN.
      # @param event_id [String] event UUID
      def pipe_handler(handler, event_data, event_id)
        options = {:data => event_data, :timeout => handler[:timeout]}
        Spawn.process(handler[:command], options) do |output, status|
          log_level = status == 0 ? :info : :error
          @logger.send(log_level, "handler output", {
            :handler => handler,
            :event => {
              :id => event_id
            },
            :output => output.split("\n+")
          })
          @in_progress[:events] -= 1 if @in_progress
        end
      end

      # Connect to a TCP socket and transmit event data to it, then
      # close the connection. The `Sensu::Server::Socket` connection
      # handler is used for the socket. The socket timeouts are
      # configurable via the handler definition, `:timeout`. The
      # `handler_error()` method is used to create the `on_error`
      # callback for the connection handler. The `on_error` callback
      # is call in the event of any error(s). The
      # `@in_progress[:events]` is decremented by `1` when the data is
      # transmitted successfully, `on_success`.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] to transmit to the TCP socket.
      # @param event_id [String] event UUID
      def tcp_handler(handler, event_data, event_id)
        unless event_data.nil? || event_data.empty?
          on_error = handler_error(handler, event_data, event_id)
          begin
            EM::connect(handler[:socket][:host], handler[:socket][:port], Socket) do |socket|
              socket.on_success = Proc.new do
                @in_progress[:events] -= 1 if @in_progress
              end
              socket.on_error = on_error
              timeout = handler[:timeout] || 10
              socket.set_timeout(timeout)
              socket.send_data(event_data.to_s)
              socket.close_connection_after_writing
            end
          rescue => error
            on_error.call(error)
          end
        else
          @logger.debug("not connecting to tcp socket due to empty event data", {
            :handler => handler,
            :event => {
              :id => event_id
            }
          })
          @in_progress[:events] -= 1 if @in_progress
        end
      end

      # Transmit event data to a UDP socket, then close the
      # connection. The `@in_progress[:events]` is decremented by `1`
      # when the data is assumed to have been transmitted.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] to transmit to the UDP socket.
      # @param event_id [String] event UUID
      def udp_handler(handler, event_data, event_id)
        begin
          EM::open_datagram_socket("0.0.0.0", 0, nil) do |socket|
            socket.send_datagram(event_data.to_s, handler[:socket][:host], handler[:socket][:port])
            socket.close_connection_after_writing
            @in_progress[:events] -= 1 if @in_progress
          end
        rescue => error
          handler_error(handler, event_data, event_id).call(error)
        end
      end

      # Publish event data to a Sensu transport pipe. Event data that
      # is `nil` or empty will not be published, to prevent transport
      # errors. The `@in_progress[:events]` is decremented by `1`,
      # even if the event data is not published.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] to publish to the transport pipe.
      # @param event_id [String] event UUID
      def transport_handler(handler, event_data, event_id)
        unless event_data.nil? || event_data.empty?
          pipe = handler[:pipe]
          pipe_options = pipe[:options] || {}
          @transport.publish(pipe[:type].to_sym, pipe[:name], event_data, pipe_options) do |info|
            if info[:error]
              handler_error(handler, event_data, event_id).call(info[:error])
            end
          end
        end
        @in_progress[:events] -= 1 if @in_progress
      end

      # Run a handler extension, within the Sensu EventMachine reactor
      # (event loop). The extension API `safe_run()` method is used to
      # guard against most errors. The `safe_run()` callback is always
      # called, logging the extension run output and status, and
      # decrementing the `@in_progress[:events]` by `1`.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] to pass to the handler extension.
      # @param event_id [String] event UUID
      def handler_extension(handler, event_data, event_id)
        handler.safe_run(event_data) do |output, status|
          log_level = (output.empty? && status.zero?) ? :debug : :info
          @logger.send(log_level, "handler extension output", {
            :extension => handler.definition,
            :event => {
              :id => event_id
            },
            :output => output,
            :status => status
          })
          @in_progress[:events] -= 1 if @in_progress
        end
      end

      # Route the event data to the appropriate handler type method.
      # Routing is done using the handler definition, `:type`.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] to pass to the handler type method.
      # @param event_id [String] event UUID
      def handler_type_router(handler, event_data, event_id)
        case handler[:type]
        when "pipe"
          pipe_handler(handler, event_data, event_id)
        when "tcp"
          tcp_handler(handler, event_data, event_id)
        when "udp"
          udp_handler(handler, event_data, event_id)
        when "transport"
          transport_handler(handler, event_data, event_id)
        when "extension"
          handler_extension(handler, event_data, event_id)
        end
      end

      # Handle an event, providing event data to an event handler.
      # This method logs event data and the handler definition at the
      # debug log level, then calls the `handler_type_router()`
      # method.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] to pass to an event handler.
      # @param event_id [String] event UUID
      def handle_event(handler, event_data, event_id)
        definition = handler.is_a?(Hash) ? handler : handler.definition
        @logger.debug("handling event", {
          :event_data => event_data,
          :event => { :id => event_id },
          :handler => definition
        })
        handler_type_router(handler, event_data, event_id)
      end
    end
  end
end
