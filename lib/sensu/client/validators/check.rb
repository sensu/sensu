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
          must_be_a_string(check[:output]) ||
            invalid(check, "check output must be a string")
          must_be_an_integer(check[:status]) ||
            invalid(check, "check status must be an integer")
          must_be_an_integer(check[:executed]) ||
            invalid(check, "check executed timestamp must be an integer")
          validate_check_name(check)
          validate_check_handling(check)
          validate_check_aggregate(check)
          validate_check_flap_detection(check)
          validate_check_truncate_output(check)
          validate_check_source(check) if check[:source]
          validate_check_ttl(check) if check[:ttl]
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
