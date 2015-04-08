require "sensu/server/socket"

module Sensu
  module Server
    module Handle
      # Create a handler error callback, for logging the error and
      # decrementing the `@handling_event_count` by `1`.
      #
      # @param handler [Object]
      # @param event_data [Object]
      # @return [Proc] error callback.
      def handler_error(handler, event_data)
        Proc.new do |error|
          @logger.error("handler error", {
            :handler => handler,
            :event_data => event_data,
            :error => error.to_s
          })
          @handling_event_count -= 1 if @handling_event_count
        end
      end

      # Execute a pipe event handler, using the defined handler
      # command to spawn a process, passing it event data via STDIN.
      # Log the handler output lines and decrement the
      # `@handling_event_count` by `1` when the handler executes
      # successfully.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] provided to the spawned handler
      #   process via STDIN.
      def pipe_handler(handler, event_data, event_id)
        options = {:data => event_data, :timeout => handler[:timeout]}
        Spawn.process(handler[:command], options) do |output, status|
          @logger.info("handler output", {
            :handler => handler,
            :event => { :id => event_id },
            :output => output.lines
          })
          @handling_event_count -= 1 if @handling_event_count
        end
      end

      # Connect to a TCP socket and transmit event data to it, then
      # close the connection. The `Sensu::Server::Socket` connection
      # handler is used for the socket. The socket timeouts are
      # configurable via the handler definition, `:timeout`. The
      # `handler_error()` method is used to create the `on_error`
      # callback for the connection handler. The `on_error` callback
      # is call in the event of any error(s). The
      # `@handling_event_count` is decremented by `1` when the data is
      # transmitted successfully, `on_success`.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] to transmit to the TCP socket.
      def tcp_handler(handler, event_data)
        on_error = handler_error(handler, event_data)
        begin
          EM::connect(handler[:socket][:host], handler[:socket][:port], Socket) do |socket|
            socket.on_success = Proc.new do
              @handling_event_count -= 1 if @handling_event_count
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
      end

      # Transmit event data to a UDP socket, then close the
      # connection. The `@handling_event_count` is decremented by `1`
      # when the data is assumed to have been transmitted.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] to transmit to the UDP socket.
      def udp_handler(handler, event_data)
        begin
          EM::open_datagram_socket("0.0.0.0", 0, nil) do |socket|
            socket.send_datagram(event_data.to_s, handler[:socket][:host], handler[:socket][:port])
            socket.close_connection_after_writing
            @handling_event_count -= 1 if @handling_event_count
          end
        rescue => error
          handler_error(handler, event_data).call(error)
        end
      end

      # Publish event data to a Sensu transport pipe. Event data that
      # is `nil` or empty will not be published, to prevent transport
      # errors. The `@handling_event_count` is decremented by `1`,
      # even if the event data is not published.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] to publish to the transport pipe.
      def transport_handler(handler, event_data)
        unless event_data.nil? || event_data.empty?
          pipe = handler[:pipe]
          pipe_options = pipe[:options] || {}
          @transport.publish(pipe[:type].to_sym, pipe[:name], event_data, pipe_options) do |info|
            if info[:error]
              handler_error(handler, event_data).call(info[:error])
            end
          end
        end
        @handling_event_count -= 1 if @handling_event_count
      end

      # Run a handler extension, within the Sensu EventMachine reactor
      # (event loop). The extension API `safe_run()` method is used to
      # guard against most errors. The `safe_run()` callback is always
      # called, logging the extension run output and status, and
      # decrementing the `@handling_event_count` by `1`.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] to pass to the handler extension.
      def handler_extension(handler, event_data, event_id)
        handler.safe_run(event_data) do |output, status|
          @logger.info("handler extension output", {
            :extension => handler.definition,
            :event => { :id => event_id },
            :output => output,
            :status => status
          })
          @handling_event_count -= 1 if @handling_event_count
        end
      end

      # Route the event data to the appropriate handler type method.
      # Routing is done using the handler definition, `:type`.
      #
      # @param handler [Hash] definition.
      # @param event_data [Object] to pass to the handler type method.
      def handler_type_router(handler, event_data, event_id)
        case handler[:type]
        when "pipe"
          pipe_handler(handler, event_data, event_id)
        when "tcp"
          tcp_handler(handler, event_data)
        when "udp"
          udp_handler(handler, event_data)
        when "transport"
          transport_handler(handler, event_data)
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
