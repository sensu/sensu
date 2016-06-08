module Sensu
  module API
    module Routes
      module Request
        REQUEST_URI = "/request".freeze

        def transport_publish_options(subscription, message)
          _, raw_type = subscription.split(":", 2).reverse
          case raw_type
          when "direct", "roundrobin"
            [:direct, subscription, message]
          else
            [:fanout, subscription, message]
          end
        end

        def publish_check_request(check)
          payload = check.merge(:issued => Time.now.to_i)
          @logger.info("publishing check request", {
            :payload => payload,
            :subscribers => check[:subscribers]
          })
          check[:subscribers].each do |subscription|
            options = transport_publish_options(subscription.to_s, Sensu::JSON.dump(payload))
            @transport.publish(*options) do |info|
              if info[:error]
                @logger.error("failed to publish check request", {
                  :subscription => subscription,
                  :payload => payload,
                  :error => info[:error].to_s
                })
              end
            end
          end
        end

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
