module Sensu
  module API
    module Routes
      module Info
        INFO_URI = "/info".freeze

        def get_info
          #          transport_info do |info|
          content = {
            :sensu => {
              :version => VERSION
            },
            :transport => {},#info,
            :redis => {
              :connected => @redis.connected?
            }
          }
          @response_status = 200
          @response_content = content
          respond!
          #          end
        end
      end
    end
  end
end
