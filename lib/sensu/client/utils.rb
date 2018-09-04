require "sensu/json"
require "sensu/client/validators/check"

module Sensu
  module Client
    module CheckUtils
      class DataError < StandardError; end

      # Validate check result attributes.
      #
      # @param [Hash] check result to validate.
      def validate_check_result(check)
        validator = Validators::Check.new
        unless validator.valid?(check)
          raise DataError, validator.failures.first[:message]
        end
      end

      # Process a check result. Set check result attribute defaults,
      # validate the attributes, publish the check result to the Sensu
      # transport, and respond to the sender with the message +"ok"+.
      #
      # @param [Hash] check result to be validated and published.
      # @raise [DataError] if +check+ is invalid.
      def process_check_result(check)
        check[:status] ||= 0
        check[:executed] ||= Time.now.to_i
        validate_check_result(check)
        publish_check_result(check)
      end

      # Publish a check result to the Sensu transport.
      #
      # @param [Hash] check result.
      def publish_check_result(check)
        payload = {
          :client => @settings[:client][:name],
          :check => check.merge(:issued => Time.now.to_i)
        }
        payload[:signature] = @settings[:client][:signature] if @settings[:client][:signature]
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
