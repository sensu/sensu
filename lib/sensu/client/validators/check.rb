require "sensu/settings/rules"
require "sensu/settings/validators/check"

module Sensu
  module Client
    module Validators
      class Check
        # Include Sensu Settings rules and check validator.
        include Sensu::Settings::Rules
        include Sensu::Settings::Validators::Check

        attr_reader :failures

        def initialize
          @failures = []
        end

        # Determine if a check definition is valid.
        #
        # @param client [Hash]
        # @return [TrueClass, FalseClass]
        def valid?(check)
          validate_check_name(check)
          validate_check_source(check) if check[:source]
          validate_check_handling(check)
          validate_check_ttl(check) if check[:ttl]
          validate_check_aggregate(check)
          validate_check_flap_detection(check)
          @failures.empty?
        end

        private

        # This method is called when `validate_check()` encounters an
        # invalid definition object. This method adds definition
        # validation failures to `@failures`.
        def invalid(object, message)
          @failures << {
            :object => object,
            :message => message
          }
        end
      end
    end
  end
end
