module Sensu
  module API
    module Utilities
      module PublishCheckResult
        # Publish a check result to the Transport for processing. A
        # check result is composed of a client name and a check
        # definition, containing check `:output` and `:status`. A client
        # signature is added to the check result payload if one is
        # registered for the client. JSON serialization is used when
        # publishing the check result payload to the Transport pipe.
        # Transport errors are logged.
        #
        # @param client_name [String]
        # @param check [Hash]
        def publish_check_result(client_name, check)
          check[:issued] = Time.now.to_i
          check[:executed] = Time.now.to_i
          check[:status] ||= 0
          payload = {
            :client => client_name,
            :check => check
          }
          @redis.get("client:#{client_name}:signature") do |signature|
            payload[:signature] = signature unless signature.nil?
            @logger.info("publishing check result", :payload => payload)
            @transport.publish(:direct, "results", Sensu::JSON.dump(payload)) do |info|
              if info[:error]
                @logger.error("failed to publish check result", {
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
