require "sensu/api/routes/info"

module Sensu
  module API
    module Routes
      module Health
        include Info

        GET_HEALTH_URI = "/health".freeze

        def get_health
          if @redis.connected? && @transport.connected?
            healthy = []
            min_consumers = integer_parameter(@params[:consumers])
            max_messages = integer_parameter(@params[:messages])
            transport_info do |info|
              if min_consumers
                healthy << (info[:keepalives][:consumers] >= min_consumers)
                healthy << (info[:results][:consumers] >= min_consumers)
              end
              if max_messages
                healthy << (info[:keepalives][:messages] <= max_messages)
                healthy << (info[:results][:messages] <= max_messages)
              end
              healthy.all? ? no_content! : precondition_failed!
            end
          else
            precondition_failed!
          end
        end
      end
    end
  end
end
