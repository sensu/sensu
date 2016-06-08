module Sensu
  module API
    module Utilities
      module PublishCheckResult
        def publish_check_result(client_name, check)
          check[:issued] = Time.now.to_i
          check[:executed] = Time.now.to_i
          check[:status] ||= 0
          payload = {
            :client => client_name,
            :check => check
          }
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
