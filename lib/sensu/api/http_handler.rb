require "sensu/api/validators"
require "sensu/api/routes"

gem "em-http-server", "0.1.8"

require "em-http-server"
require "base64"

module Sensu
  module API
    GET_METHOD = "GET".freeze
    POST_METHOD = "POST".freeze
    DELETE_METHOD = "DELETE".freeze
    OPTIONS_METHOD = "OPTIONS".freeze

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

      def parse_parameters
        @params = {}
        if @http_query_string
          @http_query_string.split("&").each do |pair|
            key, value = pair.split("=")
            @params[key.to_sym] = value
          end
        end
      end

      def integer_parameter(parameter)
        parameter =~ /\A[0-9]+\z/ ? parameter.to_i : nil
      end

      def read_data(rules={})
        begin
          data = Sensu::JSON.load(@http_content)
          valid = data.is_a?(Hash) && rules.all? do |key, rule|
            value = data[key]
            (value.is_a?(rule[:type]) || (rule[:nil_ok] && value.nil?)) &&
              (value.nil? || rule[:regex].nil?) ||
              (rule[:regex] && (value =~ rule[:regex]) == 0)
          end
          if valid
            yield(data)
          else
            bad_request!
          end
        rescue Sensu::JSON::ParseError
          bad_request!
        end
      end

      def create_response
        @response = EM::DelegatedHttpResponse.new(self)
      end

      def pagination(items)
        limit = integer_parameter(@params[:limit])
        offset = integer_parameter(@params[:offset]) || 0
        unless limit.nil?
          @response.headers["X-Pagination"] = Sensu::JSON.dump(
            :limit => limit,
            :offset => offset,
            :total => items.length
          )
          paginated = items.slice(offset, limit)
          Array(paginated)
        else
          items
        end
      end

      def respond
        @response.status = @response_status || 200
        @response.status_string = @response_status_string || "OK"
        if @response_content
          @response.content_type "application/json"
          @response.content = Sensu::JSON.dump(@response_content)
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

      def created!
        @response_status = 201
        @response_status_string = "Created"
        respond
      end

      def accepted!
        @response_status = 202
        @response_status_string = "Accepted"
        respond
      end

      def no_content!
        @response_status = 204
        @response_status_string = "No Response"
        respond
      end

      def bad_request!
        @response_status = 400
        @response_status_string = "Bad Request"
        respond
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
          when CLIENTS_URI
            get_clients
          when CLIENT_URI
            get_client
          when CLIENT_HISTORY_URI
            get_client_history
          when CHECKS_URI
            get_checks
          when CHECK_URI
            get_check
          when EVENTS_URI
            get_events
          when EVENTS_CLIENT_URI
            get_events_client
          when EVENT_URI
            get_event
          when AGGREGATES_URI
            get_aggregates
          when AGGREGATE_URI
            get_aggregate
          when AGGREGATE_CLIENTS_URI
            get_aggregate_clients
          when AGGREGATE_CHECKS_URI
            get_aggregate_checks
          when AGGREGATE_RESULTS_SEVERITY_URI
            get_aggregate_results_severity
          when STASHES_URI
            get_stashes
          when STASH_URI
            get_stash
          else
            not_found!
          end
        when POST_METHOD
          case @http_request_uri
          when CLIENTS_URI
            post_clients
          when REQUEST_URI
            post_request
          when RESOLVE_URI
            post_resolve
          when STASHES_URI
            post_stashes
          when STASH_URI
            post_stash
          else
            not_found!
          end
        when DELETE_METHOD
          case @http_request_uri
          when CLIENT_URI
            delete_client
          when EVENT_URI
            delete_event
          when AGGREGATE_URI
            delete_aggregate
          when STASH_URI
            delete_stash
          else
            not_found!
          end
        when OPTIONS_METHOD
          respond
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
