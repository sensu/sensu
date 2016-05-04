require "sensu/settings/rules"
require "sensu/settings/validators/client"

module Sensu
  module API
    module Validators
      class Invalid < RuntimeError; end

      class Client
        include Sensu::Settings::Rules
        include Sensu::Settings::Validators::Client

        def valid?(client)
          validate_client(client)
          true
        rescue Invalid
          false
        end

        private

        def invalid(*arguments)
          raise Invalid
        end
      end
    end
  end
end
