require "sensu/api/validators"
require "sensu/api/routes"

gem "em-http-server", "0.1.8"

require "em-http-server"
require "base64"

module Sensu
  module API
    GET_METHOD = "GET".freeze

    class HTTPHandler < EM::HttpServer::Server
      include Routes

      attr_accessor :logger, :settings, :redis, :transport

      def log_request
        _, @remote_address = Socket.unpack_sockaddr_in(get_peername)
        @logger.debug("request #{@http_request_method} #{@http_request_uri}", {
          :remote_address => @remote_address,
          :user_agent => @http[:user_agent],
          :request_method => @http_request_method,
          :request_uri => @http_request_uri,
          :request_query_string => @http_query_string,
          :request_body => @http_content
        })
      end

      def log_response
        @logger.info("#{@http_request_method} #{@http_request_uri}", {
          :remote_address => @remote_address,
          :user_agent => @http[:user_agent],
          :request_method => @http_request_method,
          :request_uri => @http_request_uri,
          :request_query_string => @http_query_string,
          :request_body => @http_content,
          :response_status => @response.status,
          :response_body => @response.content
        })
      end

      def integer_parameter(parameter)
        parameter =~ /\A[0-9]+\z/ ? parameter.to_i : nil
      end

      def parse_parameters
        @params = {}
        if @http_query_string
          @http_query_string.split("&").each do |pair|
            key, value = pair.split("=")
            @params[key.to_sym] = value
          end
        end
      end

      def create_response
        @response = EM::DelegatedHttpResponse.new(self)
      end

      def respond
        @response.status = @response_status || 200
        @response.status_string = @response_status_string || "OK"
        if @response_content
          @response.content_type "application/json"
          @response.content = @response_content
        end
        log_response
        @response.send_response
      end

      def authorized?
        api = @settings[:api]
        if api && api[:user] && api[:password]
          if @http[:authorization]
            scheme, base64 = @http[:authorization].split("\s")
            if scheme == "Basic"
              user, password = ::Base64.decode64(base64).split(":")
              user == api[:user] && password == api[:password]
            else
              false
            end
          else
            false
          end
        else
          true
        end
      end

      def unauthorized!
        @response.headers["WWW-Authenticate"] = 'Basic realm="Restricted Area"'
        @response_status = 401
        @response_status_string = "Unauthorized"
        respond
      end

      def not_found!
        @response_status = 404
        @response_status_string = "Not Found"
        respond
      end

      def no_content!
        @response_status = 204
        @response_status_string = "No Response"
        respond
      end

      def precondition_failed!
        @response_status = 412
        @response_status_string = "Precondition Failed"
        respond
      end

      def route_request
        case @http_request_method
        when GET_METHOD
          case @http_request_uri
          when INFO_URI
            get_info
          when HEALTH_URI
            get_health
          else
            not_found!
          end
        else
          not_found!
        end
      end

      def process_http_request
        log_request
        parse_parameters
        create_response
        if authorized?
          route_request
        else
          unauthorized!
        end
      end

      def http_request_errback(error)
        @logger.error("unexpected api error", {
          :error => error.to_s,
          :backtrace => error.backtrace.join("\n")
        })
      end
    end
  end
end
