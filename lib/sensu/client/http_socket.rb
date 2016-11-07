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

      def initialize
        super
        @endpoints = {
          "/info" => {
            "methods" => {
              "GET" => method(:process_request_info)
            },
            "help" => "Sensu client information"
          },
          "/results" => {
            "methods" => {
              "POST" => method(:process_request_results)
            },
            "help" => "Send check json results here"
          },
          "/settings" => {
            "methods" => {
              "GET" => method(:process_request_settings)
            },
            "help" => "Get sensu settings (requires basic auth)"
          }
        }
      end

      def process_request_info
        @logger.debug("Processing info request")
        rdata = {
          "response" => "ok"
        }
        rdata
      end

      def process_request_results
        @logger.debug("Processing results request")
        rdata = {
          "response" => "ok"
        }
        rdata
      end

      def process_request_settings
        @logger.debug("Processing settings request")
        rdata = {
          "response" => "ok"
        }
        rdata
      end

      def http_request_errback(ex)
        @logger.error("#{ex.class}: #{ex.message}")
      end

      # This method is called to process HTTP requests
      def process_http_request
        @logger.debug("http method: #{@http_request_method}")
        @logger.debug("http uri: #{@http_request_uri}")
        @logger.debug("http content-type: #{@http[:content_type]}")
        @logger.debug("http headers: #{@http.inspect}")
        @logger.debug("http content: #{@http_content}")
        response = EM::DelegatedHttpResponse.new(self)
        response.content_type 'application/json'
        if @endpoints[@http_request_uri]
          @logger.debug("handling known uri: #{@http_request_uri}")
          handler = @endpoints[@http_request_uri]["methods"][@http_request_method]
          if handler
            rdata = handler.call
            response.status = 200
            response.status_string = "OK"
            response.content = Sensu::JSON::dump(rdata)
          else
            response.status = 405
            response.status_string = "Method Not Allowed"
            rdata = {
              "response" => "Valid methods for this endpoint: #{@endpoints[@http_request_uri]["methods"].keys}"
            }
            response.content = Sensu::JSON::dump(rdata)
          end
        else
          @logger.warn("unknown uri: #{@http_request_uri}")
          response.status = 404
          response.status_string = "Not Found"
          rdata = {}
          @endpoints.each do |key, value|
            rdata[key] = value["help"]
          end
          @logger.debug("responding with 404", data: Sensu::JSON.dump(rdata))
          response.content = Sensu::JSON.dump(rdata)
          @logger.debug("done")
        end
        @logger.debug("sending response")
        response.send_response
      end
    end
  end
end
