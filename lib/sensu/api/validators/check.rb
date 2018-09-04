require "sensu/api/validators/invalid"
require "sensu/settings/rules"
require "sensu/settings/validators/check"

module Sensu
  module API
    module Validators
      class Check
        # Include Sensu Settings rules and check validator.
        include Sensu::Settings::Rules
        include Sensu::Settings::Validators::Check

        # Validate a check result, selectively using check definition
        # validation methods.
        #
        # @param check [Hash]
        def validate_check_result(check)
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
        end

        # Determine if a check definition is valid.
        #
        # @param check [Hash]
        # @return [TrueClass, FalseClass]
        def valid?(check)
          validate_check_result(check)
          true
        rescue Invalid
          false
        end

        private

        # This method is called when validation methods encounter an
        # invalid definition object. This method raises an exception
        # to be caught by `valid?()`.
        def invalid(*arguments)
          raise Invalid
        end
      end
    end
  end
end
