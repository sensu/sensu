module Sensu
  module API
    module Routes
      module Checks
        CHECKS_URI = "/checks".freeze
        CHECK_URI = /^\/checks\/([\w\.-]+)$/

        def get_checks
          @response_content = @settings.checks
          respond
        end

        def get_check
          check_name = CHECK_URI.match(@http_request_uri)[1]
          if @settings[:checks][check_name]
            @response_content = @settings[:checks][check_name].merge(:name => check_name)
            respond
          else
            not_found!
          end
        end
      end
    end
  end
end
