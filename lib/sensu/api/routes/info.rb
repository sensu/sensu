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
          transport_info do |transport|
            servers_info do |servers|
              @response_content = {
                :sensu => {
                  :version => VERSION,
                  :settings => {
                    :hexdigest => @settings.hexdigest
                  }
                },
                :transport => transport,
                :redis => {
                  :connected => @redis.connected?
                },
                :servers => servers
              }
              respond
            end
          end
        end
      end
    end
  end
end
