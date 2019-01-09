require "sensu/api/utilities/transport_info"

module Sensu
  module API
    module Routes
      module Health
        include Utilities::TransportInfo

        HEALTH_URI = /^\/health$/

        # GET /health
        def get_health
          @response_content = []
          if @redis.connected? && @transport.connected?
            min_consumers = integer_parameter(@params[:consumers])
            max_messages = integer_parameter(@params[:messages])
            transport_info do |info|
              if min_consumers
                if info[:keepalives][:consumers] < min_consumers
                  @response_content << "keepalive consumers (#{info[:keepalives][:consumers]}) less than min_consumers (#{min_consumers})"
                end
                if info[:results][:consumers] < min_consumers
                  @response_content << "result consumers (#{info[:results][:consumers]}) less than min_consumers (#{min_consumers})"
                end
              end
              if max_messages
                if info[:keepalives][:messages] > max_messages
                  @response_content << "keepalive messages (#{info[:keepalives][:messages]}) greater than max_messages (#{max_messages})"
                end
                if info[:results][:messages] > max_messages
                  @response_content << "result messages (#{info[:results][:messages]}) greater than max_messages (#{max_messages})"
                end
              end
              @response_content.empty? ? no_content! : precondition_failed!
            end
          else
            @response_content << "not connected to redis" unless @redis.connected?
            @response_content << "not connected to transport" unless @transport.connected?
            precondition_failed!
          end
        end
      end
    end
  end
end
