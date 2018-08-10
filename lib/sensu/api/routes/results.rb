require "sensu/api/validators/check"
require "sensu/api/utilities/publish_check_result"

module Sensu
  module API
    module Routes
      module Results
        include Utilities::PublishCheckResult

        RESULTS_URI = /^\/results$/
        RESULTS_CLIENT_URI = /^\/results\/([\w\.-]+)$/
        RESULT_URI = /^\/results\/([\w\.-]+)\/([\w\.-]+)$/

        # POST /results
        def post_results
          read_data do |check|
            check[:status] ||= 0
            check[:executed] ||= Time.now.to_i
            validator = Validators::Check.new
            if validator.valid?(check)
              publish_check_result("sensu-api", check)
              @response_content = {:issued => Time.now.to_i}
              accepted!
            else
              bad_request!
            end
          end
        end

        # GET /results
        def get_results
          @response_content = []
          @redis.smembers("clients") do |clients|
            unless clients.empty?
              result_keys = []
              clients.each_with_index do |client_name, client_index|
                @redis.smembers("result:#{client_name}") do |checks|
                  checks.each do |check_name|
                    result_keys << "result:#{client_name}:#{check_name}"
                  end
                  if client_index == clients.length - 1
                    result_keys = pagination(result_keys)
                    unless result_keys.empty?
                      result_keys.each_with_index do |result_key, result_key_index|
                        @redis.get(result_key) do |result_json|
                          history_key = result_key.sub(/^result:/, "history:")
                          @redis.lrange(history_key, -21, -1) do |history|
                            history.map! do |status|
                              status.to_i
                            end
                            unless result_json.nil?
                              client_name = history_key.split(":")[1]
                              check = Sensu::JSON.load(result_json)
                              check[:history] = history
                              @response_content << {:client => client_name, :check => check}
                            end
                            if result_key_index == result_keys.length - 1
                              respond
                            end
                          end
                        end
                      end
                    else
                      respond
                    end
                  end
                end
              end
            else
              respond
            end
          end
        end

        # GET /results/:client_name
        def get_results_client
          client_name = parse_uri(RESULTS_CLIENT_URI).first
          @response_content = []
          @redis.smembers("result:#{client_name}") do |checks|
            checks = pagination(checks)
            unless checks.empty?
              checks.each_with_index do |check_name, check_index|
                result_key = "result:#{client_name}:#{check_name}"
                @redis.get(result_key) do |result_json|
                  history_key = "history:#{client_name}:#{check_name}"
                  @redis.lrange(history_key, -21, -1) do |history|
                    history.map! do |status|
                      status.to_i
                    end
                    unless result_json.nil?
                      check = Sensu::JSON.load(result_json)
                      check[:history] = history
                      @response_content << {:client => client_name, :check => check}
                    end
                    if check_index == checks.length - 1
                      respond
                    end
                  end
                end
              end
            else
              respond
            end
          end
        end

        # GET /results/:client_name/:check_name
        def get_result
          client_name, check_name = parse_uri(RESULT_URI)
          result_key = "result:#{client_name}:#{check_name}"
          @redis.get(result_key) do |result_json|
            unless result_json.nil?
              history_key = "history:#{client_name}:#{check_name}"
              @redis.lrange(history_key, -21, -1) do |history|
                history.map! do |status|
                  status.to_i
                end
                check = Sensu::JSON.load(result_json)
                check[:history] = history
                @response_content = {:client => client_name, :check => check}
                respond
              end
            else
              not_found!
            end
          end
        end

        # DELETE /results/:client_name/:check_name
        def delete_result
          client_name, check_name = parse_uri(RESULT_URI)
          result_key = "result:#{client_name}:#{check_name}"
          @redis.exists(result_key) do |result_exists|
            if result_exists
              @redis.srem("result:#{client_name}", check_name) do
                @redis.del(result_key) do
                  history_key = "history:#{client_name}:#{check_name}"
                  @redis.del(history_key) do
                    @redis.del("#{history_key}:last_ok") do
                      no_content!
                    end
                  end
                end
              end
            else
              not_found!
            end
          end
        end
      end
    end
  end
end
