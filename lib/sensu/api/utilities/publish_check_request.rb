module Sensu
  module API
    module Utilities
      module PublishCheckRequest
        # Determine the Sensu Transport publish options for a
        # subscription. If a subscription begins with a Transport pipe
        # type, either "direct:" or "roundrobin:", the subscription uses
        # a direct Transport pipe. If a subscription does not specify a
        # Transport pipe type, a fanout Transport pipe is used.
        #
        # @param subscription [String]
        # @param message [String]
        # @return [Array] containing the Transport publish options:
        #   the Transport pipe type, pipe, and the message to be
        #   published.
        def transport_publish_options(subscription, message)
          _, raw_type = subscription.split(":", 2).reverse
          case raw_type
          when "direct", "roundrobin"
            [:direct, subscription, message]
          else
            [:fanout, subscription, message]
          end
        end

        # Publish a check request to the Transport. A check request is
        # composed of a check `:name`, an `:issued` timestamp, a check
        # `:command` if available, and a check `:extension if available.
        # The check request is published to a Transport pipe, for each
        # of the check `:subscribers` in its definition, eg. "webserver".
        # JSON serialization is used when publishing the check request
        # payload to the Transport pipes. Transport errors are logged.
        #
        # @param check [Hash] definition.
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
      end
    end
  end
end
