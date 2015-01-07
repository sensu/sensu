module Sensu
  module Server
    class Socket < EM::Connection
      attr_accessor :on_success, :on_error

      def connection_completed
        @connected_at = Time.now.to_f
        @inactivity_timeout = comm_inactivity_timeout
      end

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
