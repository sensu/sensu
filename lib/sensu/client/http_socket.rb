require "base64"
require "em-http-server"
require "sensu/json"
require "sensu/utilities"
require "sensu/api/utilities/transport_info"
require "sensu/client/utils"

module Sensu
  module Client
    # EventMachine connection handler for the Sensu HTTP client's socket.
    #
    # The Sensu client listens on localhost, port 3031 (by default), for
    # TCP HTTP connections. This allows software running on the host to
    # push check results (that may contain metrics) into Sensu, without
    # needing to know anything about Sensu's internal implementation.
    #
    # All requests and responses expect a json-encoded body (if a body
    # is expected at all).
    #
    # This socket requires receiving a proper HTTP request to any of
    # the following endpoints:
    #
    # GET /info
    #  This endpoint returns 200 OK with some basic Sensu info
    #
    # POST /results
    #  This endpoint expects application/json body with a check result
    #
    # GET /settings
    #  This endpoint responds with 200 OK and the Sensu configuration
    #
    # GET /brew
    #  This endpoint gets you some fresh coffee
    class HTTPSocket < EM::HttpServer::Server
      include Sensu::API::Utilities::TransportInfo
      include Utilities
      include CheckUtils

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
            "help" => "Send check JSON results here"
          },
          "/settings" => {
            "methods" => {
              "GET" => method(:process_request_settings)
            },
            "help" => "Get redacted Sensu settings (requires basic auth). Use ?redacted=false if you want the setting unredacted."
          },
          "/brew" => {
            "methods" => {
              "GET" => Proc.new { |response|
                send_response(418, "I'm a teapot", {
                  :response => "I'm a teapot!"
                })
              }
            },
            "help" => "Ask Sensu to brew a cup of joe (try it!)"
          }
        }
        @response = nil
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

      def send_response(status, status_string, content)
        @logger.debug("sending HTTP response #{status} #{status_string}", :content => content)
        @response.status = status
        @response.status_string = status_string
        @response.content = Sensu::JSON::dump(content)
        @response.send_response
      end

      def process_request_info
        transport_info do |info|
          send_response(200, "OK", {
            :sensu => {
              :version => VERSION
            },
            :transport => info
          })
        end
      end

      def process_request_results
        if @http[:content_type] and @http[:content_type] == "application/json" and @http_content
          begin
            check = Sensu::JSON::load(@http_content)
            process_check_result(check)
            send_response(202, "OK", {:response => "ok"})
          rescue Sensu::JSON::ParseError, ArgumentError
            send_response(400, "Failed to parse JSON body", {:response => "Failed to parse JSON body"})
          end
        else
          send_response(415, "Only application/json content type accepted", {:response => "Invalid content type"})
        end
      end

      def process_request_settings
        if authorized?
          @logger.info("responding to HTTP request for configuration settings")
          if @http_query_string and @http_query_string.downcase.include?("redacted=false")
            send_response(200, "OK", @settings.to_hash)
          else
            send_response(200, "OK", redact_sensitive(@settings.to_hash))
          end
        else
          @logger.warn("refusing to serve unauthorized settings request")
          @response.headers["WWW-Authenticate"] = 'Basic realm="Sensu Client Restricted Area"'
          send_response(401, "Unauthorized", {
            :response => "You must be authenticated using your http_options user and password settings"
          })
        end
      end

      def http_request_errback(ex)
        @logger.error("exception while processing HTTP request: #{ex.class}: #{ex.message}", backtrace: ex.backtrace)
        @response = EM::DelegatedHttpResponse.new(self)
        @response.content_type "application/json"
        send_response(500, "Internal Server Error", {
          "response" => "Internal Server Error: Check your Sensu logs for error details"
        })
      end

      # This method is called to process HTTP requests
      def process_http_request
        @logger.debug("processing #{@http_request_method} #{@http_request_uri}")
        @response = EM::DelegatedHttpResponse.new(self)
        @response.content_type "application/json"
        endpoint = @endpoints[@http_request_uri]
        if endpoint
          @logger.debug("endpoint #{@http_request_uri} found", :accepted_methods => endpoint["methods"].keys)
          method_name = @http_request_method.upcase
          method_handler = endpoint["methods"][method_name]
          if method_handler
            @logger.debug("executing #{method_name} #{@http_request_uri} handler")
            method_handler.call
          else
            @logger.debug("method #{method_name} is not allowed for endpoint #{@http_request_uri}")
            send_response(405, "Method Not Allowed", {
              :response => "Valid methods for this endpoint: #{reqdef['methods'].keys}"
            })
          end
        else
          @logger.warn("unknown endpoint requested: #{@http_request_uri}")
          help_response = {
            :endpoints => {}
          }
          @endpoints.each do |key, value|
            help_response[:endpoints][key] ||= Hash.new
            help_response[:endpoints][key]["help"] = value["help"]
            help_response[:endpoints][key]["methods"] = value["methods"].keys
          end
          send_response(404, "Not Found", help_response)
        end
      end
    end
  end
end
