require "sensu/api/utilities/publish_check_request"

module Sensu
  module API
    module Routes
      module Request
        include Utilities::PublishCheckRequest

        REQUEST_URI = "/request".freeze

        def post_request
          rules = {
            :check => {:type => String, :nil_ok => false},
            :subscribers => {:type => Array, :nil_ok => true}
          }
          read_data(rules) do |data|
            if @settings[:checks][data[:check]]
              check = @settings[:checks][data[:check]].dup
              check[:name] = data[:check]
              check[:subscribers] ||= Array.new
              check[:subscribers] = data[:subscribers] if data[:subscribers]
              publish_check_request(check)
              @response_content = {:issued => Time.now.to_i}
              accepted!
            else
              not_found!
            end
          end
        end
      end
    end
  end
end
