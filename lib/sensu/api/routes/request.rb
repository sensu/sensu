require "sensu/api/utilities/publish_check_request"

module Sensu
  module API
    module Routes
      module Request
        include Utilities::PublishCheckRequest

        REQUEST_URI = /^\/request$/

        # POST /request
        def post_request
          rules = {
            :check => {:type => String, :nil_ok => false},
            :subscribers => {:type => Array, :nil_ok => true},
            :reason => {:type => String, :nil_ok => true},
            :creator => {:type => String, :nil_ok => true}
          }
          read_data(rules) do |data|
            if @settings[:checks][data[:check]]
              check = @settings[:checks][data[:check]].dup
              check[:name] = data[:check]
              check[:subscribers] ||= Array.new
              check[:subscribers] = data[:subscribers] if data[:subscribers]
              check[:api_requested] = {
                :reason => data[:reason],
                :creator => data[:creator]
              }
              if check[:proxy_requests]
                publish_proxy_check_requests(check)
              else
                publish_check_request(check)
              end
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
