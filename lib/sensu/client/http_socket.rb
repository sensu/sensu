require "base64"
require "em-http-server"
require "sensu/json"
require "sensu/utilities"
require "sensu/api/utilities/transport_info"

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
      include Sensu::API::Utilities::TransportInfo
      include Utilities

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

      def authorized?
        http_options = @settings[:client][:http_socket] || Hash.new
        if http_options[:user] and http_options[:password]
          if @http[:authorization]
            scheme, base64 = @http[:authorization].split("\s")
            if scheme == "Basic"
              user, password = Base64.decode64(base64).split(":")
              return (user == http_options[:user] && password == http_options[:password])
            end
          end
        end
        false
      end

      def process_request_info(response)
        @logger.debug("Processing info request")
        transport_info do |info|
          rdata = {
            :sensu => {
              :version => VERSION
            },
            :transport => info
          }
          response.content = Sensu::JSON::dump(rdata)
          response.send_response
        end
      end

      def process_request_results(response)
        @logger.debug("Processing results request")
        rdata = {
          :response => "ok"
        }
        response.content = Sensu::JSON::dump(rdata)
        response.send_response
      end

      def process_request_settings(response)
        if authorized?
          @logger.debug("Processing settings request")
          if @http_query_string and @http_query_string.downcase.include?('redacted=false')
            response.content = Sensu::JSON::dump(@settings.to_hash)
          else
            response.content = Sensu::JSON::dump(redact_sensitive(@settings.to_hash))
          end
          response.send_response
        else
          @logger.warn("Refusing to serve unauthorized settings request")
          rdata = {:response => "You must be authenticated using your http_options user and password settings"}
          response.headers["WWW-Authenticate"] = 'Basic realm="Sensu Client Restricted Area"'
          response.status = 401
          response.status_string = "Unauthorized"
          response.content = Sensu::JSON::dump(rdata)
          response.send_response
        end
      end

      def http_request_errback(ex)
        @logger.error("Exception while processing HTTP request: #{ex.class}: #{ex.message}", backtrace: ex.backtrace)
        response = EM::DelegatedHttpResponse.new(self)
        response.content_type 'application/json'
        response.status = 500
        response.status_string = "Internal Server Error"
        rdata = {
          "response" => "Internal Server Error: Check your sensu logs for error details"
        }
        response.content = Sensu::JSON::dump(rdata)
        response.send_response
      end

      # This method is called to process HTTP requests
      def process_http_request
        @logger.debug("Processing #{@http_request_method} #{@http_request_uri}")
        response = EM::DelegatedHttpResponse.new(self)
        response.content_type 'application/json'
        reqdef = @endpoints[@http_request_uri]
        if reqdef
          handler = reqdef["methods"][@http_request_method.upcase]
          if handler
            response.status = 200
            response.status_string = "OK"
            handler.call(response)
          else
            response.status = 405
            response.status_string = "Method Not Allowed"
            rdata = {
              :response => "Valid methods for this endpoint: #{reqdef['methods'].keys}"
            }
            response.content = Sensu::JSON::dump(rdata)
            response.send_response
          end
        else
          @logger.warn("Unknown uri requested: #{@http_request_uri}")
          response.status = 404
          response.status_string = "Not Found"
          rdata = {
            :endpoints => {}
          }
          @endpoints.each do |key, value|
            rdata[:endpoints][key] ||= Hash.new
            rdata[:endpoints][key]["help"] = value["help"]
            rdata[:endpoints][key]["methods"] = value["methods"].keys
          end
          @logger.debug("Responding with 404", response: Sensu::JSON.dump(rdata))
          response.content = Sensu::JSON.dump(rdata)
          response.send_response
        end
      end
    end
  end
end
