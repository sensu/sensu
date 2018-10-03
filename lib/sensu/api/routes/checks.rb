module Sensu
  module API
    module Routes
      module Checks
        CHECKS_URI = /^\/checks$/
        CHECK_URI = /^\/checks\/([\w\.-]+)$/

        # GET /checks
        def get_checks
          checks = @settings.checks.reject { |check| check[:standalone] }
          @response_content = pagination(checks)
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

        # DELETE /checks/:check_name
        def delete_check
          # history:*:check_name
          # history:*:check_name:last_ok
          # result:*:check_name
          check_name = parse_uri(CHECK_URI).first
          @redis.keys("result:*:#{check_name}") do |result_keys|
            @redis.keys("history:*:#{check_name}") do |history_keys|
              @redis.keys("history:*:#{check_name}:last_ok") do |last_ok_keys|
                keys = result_keys.concat(history_keys).concat(last_ok_keys)
                keys.each do |key|
                  @redis.del(key)
                end
              end
            end
          end
          @response_content = {:issued => Time.now.to_i}
          accepted!
        end
      end
    end
  end
end
