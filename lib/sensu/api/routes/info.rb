require "sensu/api/utilities/transport_info"
require "sensu/api/utilities/servers_info"

module Sensu
  module API
    module Routes
      module Info
        include Utilities::TransportInfo
        include Utilities::ServersInfo

        INFO_URI = /^\/info$/

        # GET /info
        def get_info
          transport_info do |transport_info|
            servers_info do |servers_info|
              @response_content = {
                :sensu => {
                  :version => VERSION
                },
                :transport => transport_info,
                :redis => {
                  :connected => @redis.connected?
                },
                :servers => servers_info
              }
              respond
            end
          end
        end
      end
    end
  end
end
