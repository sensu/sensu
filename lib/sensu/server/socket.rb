module Sensu
  module Server
    class Socket < EM::Connection
      # @!attribute [rw] on_success
      # @return [Proc] callback to be called after the data has been
      #   transmitted successfully.
      attr_accessor :on_success

      # @!attribute [rw] on_error
      # @return [Proc] callback to be called when there is an error.
      attr_accessor :on_error

      # Create a timeout timer to immediately close the socket
      # connection and set `@timed_out` to true to indicate that the
      # timeout caused the connection to close. The timeout timer is
      # stored with `@timeout_timer`, so that it can be cancelled when
      # the connection is closed.
      #
      # @param timeout [Numeric] in seconds.
      def set_timeout(timeout)
        @timeout_timer = Timer.new(timeout) do
          @timed_out = true
          close_connection
        end
      end

      # Record the current time when connected.
      def connection_completed
        @connected_at = Time.now.to_f
      end

      # Determine if the connection and data transmission was
      # successful and call the appropriate callback, `@on_success`
      # or `@on_error`, providing it with a message. Cancel the
      # connection timeout timer `@timeout_timer`, if it is set. The
      # `@connected_at` timestamp indicates that the connection was
      # successful. If `@timed_out` is true, the connection was closed
      # by the connection timeout, and the data is assumed to not have
      # been transmitted.
      def unbind
        @timeout_timer.cancel if @timeout_timer
        if @connected_at
          if @timed_out
            @on_error.call("socket timeout")
          else
            @on_success.call("wrote to socket")
          end
        else
          @on_error.call("failed to connect to socket")
        end
      end
    end
  end
end
