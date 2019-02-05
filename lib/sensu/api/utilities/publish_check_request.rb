require "sensu/utilities"

module Sensu
  module API
    module Utilities
      module PublishCheckRequest
        include Sensu::Utilities

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
          payload = check.reject do |key, value|
            [:subscribers, :interval].include?(key)
          end
          payload[:issued] = Time.now.to_i
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

        # Create and publish one or more proxy check requests. This
        # method iterates through the Sensu client registry for clients
        # that matched provided proxy request client attributes. A proxy
        # check request is created for each client in the registry that
        # matches the proxy request client attributes. Proxy check
        # requests have their client tokens subsituted by the associated
        # client attributes values. The check requests are published to
        # the Transport via `publish_check_request()`.
        #
        # @param check [Hash] definition.
        def publish_proxy_check_requests(check)
          client_attributes = check[:proxy_requests][:client_attributes]
          unless client_attributes.empty?
            @redis.smembers("clients") do |clients|
              clients.each do |client_name|
                @redis.get("client:#{client_name}") do |client_json|
                  unless client_json.nil?
                    client = Sensu::JSON.load(client_json)
                    if attributes_match?(client, client_attributes)
                      @logger.debug("creating a proxy check request", {
                        :client => client,
                        :check => check
                      })
                      proxy_check, unmatched_tokens = object_substitute_tokens(deep_dup(check.dup), client)
                      if unmatched_tokens.empty?
                        proxy_check[:source] ||= client[:name]
                        publish_check_request(proxy_check)
                      else
                        @logger.warn("failed to publish a proxy check request", {
                          :reason => "unmatched client tokens",
                          :unmatched_tokens => unmatched_tokens,
                          :client => client,
                          :check => check
                        })
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
