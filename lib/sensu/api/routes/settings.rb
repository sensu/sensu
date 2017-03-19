require "sensu/utilities"

module Sensu
  module API
    module Routes
      module Settings
        include Utilities

        SETTINGS_URI = /^\/settings$/

        # GET /settings
        def get_settings
          if @params[:redacted] == "false"
            @response_content = @settings.to_hash
          else
            @response_content = redact_sensitive(@settings.to_hash)
          end
          respond
        end
      end
    end
  end
end
