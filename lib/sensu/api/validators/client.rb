require "sensu/api/validators/invalid"
require "sensu/settings/rules"
require "sensu/settings/validators/client"

module Sensu
  module API
    module Validators
      class Client
        # Include Sensu Settings rules and client validator.
        include Sensu::Settings::Rules
        include Sensu::Settings::Validators::Client

        # Determine if a client definition is valid.
        #
        # @param client [Hash]
        # @return [TrueClass, FalseClass]
        def valid?(client)
          validate_client(client)
          true
        rescue Invalid
          false
        end

        private

        # This method is called when `validate_client()` encounters an
        # invalid definition object. This method raises an exception
        # to be caught by `valid?()`.
        def invalid(*arguments)
          raise Invalid
        end
      end
    end
  end
end
