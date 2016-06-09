require "sensu/api/utilities/transport_info"

module Sensu
  module API
    module Routes
      module Info
        include Utilities::TransportInfo

        INFO_URI = /^\/info$/

        def get_info
          transport_info do |info|
            @response_content = {
              :sensu => {
                :version => VERSION
              },
              :transport => info,
              :redis => {
                :connected => @redis.connected?
              }
            }
            respond
          end
        end
      end
    end
  end
end
