module Sensu
  module API
    module Routes
      module Clients
        GET_CLIENTS_URI = "/clients".freeze
        GET_CLIENT_URI = /^\/clients\/([\w\.-]+)$/

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
      end
    end
  end
end
