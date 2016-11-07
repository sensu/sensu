require "em-http-server"
require "sensu/json"

module Sensu
  module Client
    # EventMachine connection handler for the Sensu HTTP client"s socket.
    #
    # The Sensu client listens on localhost, port 3031 (by default), for
    # TCP HTTP connections. This allows software running on the host to
    # push check results (that may contain metrics) into Sensu, without
    # needing to know anything about Sensu"s internal implementation.
    #
    # All requests and responses expect a json-encoded body (if a body
    # is expected at all).
    #
    # This socket requires receiving a proper HTTP request to any of
    # the following endpoints:
    #
    # /ping
    #  This endpoint will simply return a 200 OK with a pong response
    #
    # /check
    #  This endpoint expects application/json body with a check
    #
    # /settings
    #  This endpoint will respond with the sensu configuration
    class HTTPSocket < EM::HttpServer::Server

      attr_accessor :logger, :settings, :transport

      # This method is called to process HTTP requests
      def process_http_request
        @logger.debug("http method: #{@http_request_method}")
        @logger.debug("http uri: #{@http_request_uri}")
        @logger.debug("http content-type: #{@http[:content_type]}")
        @logger.debug("http content: #{@http_content}")
        @logger.debug("http headers: #{@http.inspect}")
        response = EM::DelegatedHttpResponse.new(self)
        response.status = 200
        response.content_type 'application/json'
        response.content = '{"response": "ok"}'
        response.send_response
      end
    end
  end
end
