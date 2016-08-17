module Sensu
  module API
    module Routes
      module Checks
        CHECKS_URI = /^\/checks$/
        CHECK_URI = /^\/checks\/([\w\.-]+)$/

        # GET /checks
        def get_checks
          @response_content = @settings.checks.reject { |check| check[:standalone] }
          respond
        end

        # GET /checks/:check_name
        def get_check
          check_name = parse_uri(CHECK_URI).first
          if @settings[:checks][check_name] && !@settings[:checks][check_name][:standalone]
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
