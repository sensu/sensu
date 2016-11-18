require "sensu/json"

module Sensu
  module Client
    module CheckUtils
      class DataError < StandardError; end
      # Validate check result attributes.
      #
      # @param [Hash] check result to validate.
      def validate_check_result(check)
        unless check[:name] =~ /\A[\w\.-]+\z/
          raise DataError, "check name must be a string and cannot contain spaces or special characters"
        end
        unless check[:source].nil? || check[:source] =~ /\A[\w\.-]+\z/
          raise DataError, "check source must be a string and cannot contain spaces or special characters"
        end
        unless check[:output].is_a?(String)
          raise DataError, "check output must be a string"
        end
        unless check[:status].is_a?(Integer)
          raise DataError, "check status must be an integer"
        end
        unless check[:executed].is_a?(Integer)
          raise DataError, "check executed timestamp must be an integer"
        end
        unless check[:ttl].nil? || (check[:ttl].is_a?(Integer) && check[:ttl] > 0)
          raise DataError, "check ttl must be an integer greater than 0"
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
