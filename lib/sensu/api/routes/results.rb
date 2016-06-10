require "sensu/api/utilities/publish_check_result"

module Sensu
  module API
    module Routes
      module Results
        include Utilities::PublishCheckResult

        RESULTS_URI = /^\/results$/
        RESULTS_CLIENT_URI = /^\/results\/([\w\.-]+)$/
        RESULT_URI = /^\/results\/([\w\.-]+)\/([\w\.-]+)$/

        def post_results
          rules = {
            :name => {:type => String, :nil_ok => false, :regex => /\A[\w\.-]+\z/},
            :output => {:type => String, :nil_ok => false},
            :status => {:type => Integer, :nil_ok => true},
            :source => {:type => String, :nil_ok => true, :regex => /\A[\w\.-]+\z/}
          }
          read_data(rules) do |data|
            publish_check_result("sensu-api", data)
            @response_content = {:issued => Time.now.to_i}
            accepted!
          end
        end

        def get_results
          @response_content = []
          @redis.smembers("clients") do |clients|
            unless clients.empty?
              clients.each_with_index do |client_name, client_index|
                @redis.smembers("result:#{client_name}") do |checks|
                  if !checks.empty?
                    checks.each_with_index do |check_name, check_index|
                      result_key = "result:#{client_name}:#{check_name}"
                      @redis.get(result_key) do |result_json|
                        unless result_json.nil?
                          check = Sensu::JSON.load(result_json)
                          @response_content << {:client => client_name, :check => check}
                        end
                        if client_index == clients.length - 1 && check_index == checks.length - 1
                          respond
                        end
                      end
                    end
                  elsif client_index == clients.length - 1
                    respond
                  end
                end
              end
            else
              respond
            end
          end
        end

        def get_results_client
          client_name = parse_uri(RESULTS_CLIENT_URI).first
          @response_content = []
          @redis.smembers("result:#{client_name}") do |checks|
            unless checks.empty?
              checks.each_with_index do |check_name, check_index|
                result_key = "result:#{client_name}:#{check_name}"
                @redis.get(result_key) do |result_json|
                  unless result_json.nil?
                    check = Sensu::JSON.load(result_json)
                    @response_content << {:client => client_name, :check => check}
                  end
                  if check_index == checks.length - 1
                    respond
                  end
                end
              end
            else
              not_found!
            end
          end
        end

        def get_result
          client_name, check_name = parse_uri(RESULT_URI)
          result_key = "result:#{client_name}:#{check_name}"
          @redis.get(result_key) do |result_json|
            unless result_json.nil?
              check = Sensu::JSON.load(result_json)
              @response_content = {:client => client_name, :check => check}
              respond
            else
              not_found!
            end
          end
        end

        def delete_result
          client_name, check_name = parse_uri(RESULT_URI)
          result_key = "result:#{client_name}:#{check_name}"
          @redis.exists(result_key) do |result_exists|
            if result_exists
              @redis.srem("result:#{client_name}", check_name) do
                @redis.del(result_key) do
                  no_content!
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
