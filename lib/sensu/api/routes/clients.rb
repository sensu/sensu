module Sensu
  module API
    module Routes
      module Clients
        GET_CLIENTS_URI = "/clients".freeze
        GET_CLIENT_URI = /^\/clients\/([\w\.-]+)$/
        GET_CLIENT_HISTORY_URI = /^\/clients\/([\w\.-]+)\/history$/

        def get_clients
          @response_content = []
          @redis.smembers("clients") do |clients|
            clients = pagination(clients)
            unless clients.empty?
              clients.each_with_index do |client_name, index|
                @redis.get("client:#{client_name}") do |client_json|
                  unless client_json.nil?
                    @response_content << Sensu::JSON.load(client_json)
                  else
                    @logger.error("client data missing from registry", :client_name => client_name)
                    @redis.srem("clients", client_name)
                  end
                  if index == clients.length - 1
                    respond
                  end
                end
              end
            else
              respond
            end
          end
        end

        def get_client
          client_name = GET_CLIENT_URI.match(@http_request_uri)[1]
          @redis.get("client:#{client_name}") do |client_json|
            unless client_json.nil?
              @response_content = client_json
              respond
            else
              not_found!
            end
          end
        end

        def get_client_history
          client_name = GET_CLIENT_HISTORY_URI.match(@http_request_uri)[1]
          @response_content = []
          @redis.smembers("result:#{client_name}") do |checks|
            unless checks.empty?
              checks.each_with_index do |check_name, index|
                result_key = "#{client_name}:#{check_name}"
                history_key = "history:#{result_key}"
                @redis.lrange(history_key, -21, -1) do |history|
                  history.map! do |status|
                    status.to_i
                  end
                  @redis.get("result:#{result_key}") do |result_json|
                    unless result_json.nil?
                      result = Sensu::JSON.load(result_json)
                      last_execution = result[:executed]
                      unless history.empty? || last_execution.nil?
                        item = {
                          :check => check_name,
                          :history => history,
                          :last_execution => last_execution.to_i,
                          :last_status => history.last,
                          :last_result => result
                        }
                        @response_content << item
                      end
                    end
                    if index == checks.length - 1
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
    end
  end
end
