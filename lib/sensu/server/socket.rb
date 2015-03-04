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

      # Record the current time and the inactivity timeout value, when
      # the socket connection is successful. These values are used to
      # determine if the a connection was closed due to the timeout.
      def connection_completed
        @connected_at = Time.now.to_f
        @inactivity_timeout = comm_inactivity_timeout
      end

      # Determine if the connection and data transmission was
      # successful and call the appropriate callback, `@on_success`
      # or `@on_error`, providing it with a message. The
      # `@connected_at` timestamp indicates that the connection was
      # successful. If the elapsed time is greater than the inactivity
      # timeout value, the connection was closed abruptly by the
      # timeout timer, and the data was not transmitted.
      def unbind
        if @connected_at
          elapsed_time = Time.now.to_f - @connected_at
          if elapsed_time >= @inactivity_timeout
            @on_error.call("socket inactivity timeout")
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
