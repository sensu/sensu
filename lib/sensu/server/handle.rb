require "sensu/server/socket"

module Sensu
  module Server
    module Handle
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

      def pipe_handler(handler, event_data)
        options = {:data => event_data, :timeout => handler[:timeout]}
        Spawn.process(handler[:command], options) do |output, status|
          @logger.info("handler output", {
            :handler => handler,
            :output => output.lines
          })
          @handling_event_count -= 1 if @handling_event_count
        end
      end

      def tcp_handler(handler, event_data)
        on_error = handler_error(handler, event_data)
        begin
          EM::connect(handler[:socket][:host], handler[:socket][:port], SocketHandler) do |socket|
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

      def transport_handler(handler, event_data)
        unless event_data.empty?
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

      def handler_extension(handler, event_data)
        handler.safe_run(event_data) do |output, status|
          @logger.info("handler extension output", {
            :extension => handler.definition,
            :output => output
          })
          @handling_event_count -= 1 if @handling_event_count
        end
      end

      def handler_type_router(handler, event_data)
        case handler[:type]
        when "pipe"
          pipe_handler(handler, event_data)
        when "tcp"
          tcp_handler(handler, event_data)
        when "udp"
          udp_handler(handler, event_data)
        when "transport"
          transport_handler(handler, event_data)
        when "extension"
          handler_extension(handler, event_data)
        end
      end

      def handle_event(handler, event_data)
        definition = handler.is_a?(Hash) ? handler : handler.definition
        @logger.debug("handling event", {
          :event_data => event_data,
          :handler => definition
        })
        handler_type_router(handler, event_data)
      end
    end
  end
end
