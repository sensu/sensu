require "sensu/utilities"
require "sensu/api/routes"
require "sensu/api/utilities/filter_response_content"

gem "em-http-server", "0.1.8"

require "em-http-server"
require "base64"

module Sensu
  module API
    class HTTPHandler < EM::HttpServer::Server
      include Routes
      include Utilities::FilterResponseContent

      attr_accessor :logger, :settings, :redis, :transport

      # Create a hash containing the HTTP request details. This method
      # determines the remote address for the HTTP client (using
      # EventMachine Connection `get_peername()`).
      #
      # @result [Hash]
      def request_details
        return @request_details if @request_details
        @request_id = @http.fetch(:x_request_id, random_uuid)
        @request_start_time = Time.now.to_f
        _, remote_address = Socket.unpack_sockaddr_in(get_peername)
        @request_details = {
          :request_id => @request_id,
          :remote_address => remote_address,
          :user_agent => @http[:user_agent],
          :method => @http_request_method,
          :uri => @http_request_uri,
          :query_string => @http_query_string,
          :body => @http_content
        }
        if @http[:x_forwarded_for]
          @request_details[:x_forwarded_for] = @http[:x_forwarded_for]
        end
        @request_details
      end

      # Log the HTTP request. The debug log level is used for requests
      # as response logging includes the same information.
      def log_request
        @logger.debug("api request", request_details)
      end

      # Log the HTTP response. This method calculates the
      # request/response time. The debug log level is used for the
      # response body log event, as it is generally very verbose and
      # unnecessary in most cases.
      def log_response
        @logger.info("api response", {
          :request => request_details,
          :status => @response.status,
          :content_length => @response.content.to_s.bytesize,
          :time => (Time.now.to_f - @request_start_time).round(3)
        })
      end

      # Parse the HTTP request URI using a regular expression,
      # returning the URI unescaped match data values.
      #
      # @param regex [Regexp]
      # @return [Array] URI unescaped match data values.
      def parse_uri(regex)
        uri_match = regex.match(@http_request_uri)[1..-1]
        uri_match.map { |s| URI.unescape(s) }
      end

      # Parse the HTTP request query string for parameters. This
      # method creates `@params`, a hash of parsed query parameters,
      # used by the API routes. This method also creates
      # `@filter_params`, a hash of parsed response content filter
      # parameters.
      def parse_parameters
        @params = {}
        if @http_query_string
          @http_query_string.split("&").each do |pair|
            key, value = pair.split("=")
            @params[key.to_sym] = value
            if key.start_with?("filter.")
              filter_param = key.sub(/^filter\./, "")
              @filter_params ||= {}
              @filter_params[filter_param] = value
            end
          end
        end
      end

      # Determine if a parameter has an integer value and if so return
      # it as one. This method will return `nil` if the parameter
      # value is not an integer.
      #
      # @param value [String]
      # @return [Integer, nil]
      def integer_parameter(value)
        value =~ /\A[0-9]+\z/ ? value.to_i : nil
      end

      # Read JSON data from the HTTP request content and validate it
      # with the provided rules. If the HTTP request content does not
      # contain valid JSON or it does not pass validation, this method
      # returns a `400` (Bad Request) HTTP response.
      #
      # @param rules [Hash] containing the validation rules.
      # @yield [Object] the callback/block called with the data after successfully
      #   parsing and validating the the HTTP request content.
      def read_data(rules={})
        begin
          data = Sensu::JSON.load(@http_content)
          valid = data.is_a?(Hash) && rules.all? do |key, rule|
            value = data[key]
            (Array(rule[:type]).any? {|type| value.is_a?(type)} ||
              (rule[:nil_ok] && value.nil?)) && (value.nil? || rule[:regex].nil?) ||
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

      # Create an EM HTTP Server HTTP response object, `@response`.
      # The response object is use to build up the response status,
      # status string, content type, and content. The response object
      # is responsible for sending the HTTP response to the HTTP
      # client and closing the connection afterwards.
      #
      # @return [Object]
      def create_response
        @response = EM::DelegatedHttpResponse.new(self)
      end

      # Set the cors (Cross-origin resource sharing) HTTP headers.
      def set_cors_headers
        api = @settings[:api] || {}
        api[:cors] ||= {
          "Origin" => "*",
          "Methods" => "GET, POST, PUT, DELETE, OPTIONS",
          "Credentials" => "true",
          "Headers" => "Origin, X-Requested-With, Content-Type, Accept, Authorization"
        }
        if api[:cors].is_a?(Hash)
          api[:cors].each do |header, value|
            @response.headers["Access-Control-Allow-#{header}"] = value
          end
        end
      end

      # Set the HTTP response headers, including the request ID and
      # cors headers (via `set_cores_headers()`).
      def set_headers
        @response.headers["X-Request-ID"] = @request_id
        set_cors_headers
      end

      # Paginate the provided items. This method uses two HTTP query
      # parameters to determine how to paginate the items, `limit` and
      # `offset`. The parameter `limit` specifies how many items are
      # to be returned in the response. The parameter `offset`
      # specifies the items array index, skipping a number of items.
      # This method sets the "X-Pagination" HTTP response header to a
      # JSON object containing the `limit`, `offset` and `total`
      # number of items that are being paginated.
      #
      # @param items [Array]
      # @return [Array] paginated items.
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

      # Respond to an HTTP request. The routes set `@response_status`,
      # `@response_status_string`, and `@response_content`
      # appropriately. The HTTP response status defaults to `200` with
      # the status string `OK`. If filter params were provided,
      # `@response_content` is filtered (mutated). The Sensu API only
      # returns JSON response content, `@response_content` is assumed
      # to be a Ruby object that can be serialized as JSON.
      def respond
        @response.status = @response_status || 200
        @response.status_string = @response_status_string || "OK"
        if @response_content && @http_request_method != HEAD_METHOD
          if @http_request_method == GET_METHOD && @filter_params
            filter_response_content!
          end
          @response.content_type "application/json"
          @response.content = Sensu::JSON.dump(@response_content)
        end
        @response.headers["Connection"] = "close"
        log_response
        @response.send_response
      end

      # Determine if an HTTP request is authorized. This method
      # compares the configured API user and password (if any) with
      # the HTTP request basic authentication credentials. No
      # authentication is done if the API user and password are not
      # configured. OPTIONS HTTP requests bypass authentication.
      #
      # @return [TrueClass, FalseClass]
      def authorized?
        api = @settings[:api]
        if api && api[:user] && api[:password]
          if @http_request_method == OPTIONS_METHOD
            true
          elsif @http[:authorization]
            scheme, base64 = @http[:authorization].split("\s")
            if scheme == "Basic"
              user, password = Base64.decode64(base64).split(":")
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

      # Determine if the API is connected to Redis and the Transport.
      # This method sets the `@response_content` if the API is not
      # connected or it has not yet initialized the connection
      # objects. The `/info` and `/health` routes are excluded from
      # the connectivity checks.
      def connected?
        connected = true
        if @redis && @transport
          unless @http_request_uri =~ INFO_URI || @http_request_uri =~ HEALTH_URI
            unless @redis.connected?
              @response_content = {:error => "not connected to redis"}
              connected = false
            end
            unless @transport.connected?
              @response_content = {:error => "not connected to transport"}
              connected = false
            end
          end
        else
          @response_content = {:error => "redis and transport connections not initialized"}
          connected = false
        end
        connected
      end

      # Respond to the HTTP request with a `201` (Created) response.
      def created!
        @response_status = 201
        @response_status_string = "Created"
        respond
      end

      # Respond to the HTTP request with a `202` (Accepted) response.
      def accepted!
        @response_status = 202
        @response_status_string = "Accepted"
        respond
      end

      # Respond to the HTTP request with a `204` (No Content)
      # response.
      def no_content!
        @response_status = 204
        @response_status_string = "No Content"
        @response_content = nil
        respond
      end

      # Respond to the HTTP request with a `400` (Bad Request)
      # response.
      def bad_request!
        @response_status = 400
        @response_status_string = "Bad Request"
        respond
      end

      # Respond to the HTTP request with a `401` (Unauthroized)
      # response. This method sets the "WWW-Autenticate" HTTP response
      # header.
      def unauthorized!
        @response.headers["WWW-Authenticate"] = 'Basic realm="Restricted Area"'
        @response_status = 401
        @response_status_string = "Unauthorized"
        respond
      end

      # Respond to the HTTP request with a `404` (Not Found) response.
      def not_found!
        @response_status = 404
        @response_status_string = "Not Found"
        respond
      end

      # Respond to the HTTP request with a `405` (Method Not Allowed) response.
      def method_not_allowed!(allowed_http_methods=[])
        @response.headers["Allow"] = allowed_http_methods.join(", ")
        @response_status = 405
        @response_status_string = "Method Not Allowed"
        respond
      end

      # Respond to the HTTP request with a `412` (Precondition Failed)
      # response.
      def precondition_failed!
        @response_status = 412
        @response_status_string = "Precondition Failed"
        respond
      end

      # Respond to the HTTP request with a `500` (Internal Server
      # Error) response.
      def error!
        @response_status = 500
        @response_status_string = "Internal Server Error"
        respond
      end

      # Determine the allowed HTTP methods for a route. The route
      # regular expressions and associated route method calls are
      # provided by `ROUTES`. This method returns an array of HTTP
      # methods that have a route that matches the HTTP request URI.
      #
      # @return [Array]
      def allowed_http_methods?
        ROUTES.map { |http_method, routes|
          match = routes.detect do |route|
            @http_request_uri =~ route[0]
          end
          match ? http_method : nil
        }.flatten.compact
      end

      # Determine the route method for the HTTP request method and
      # URI. The route regular expressions and associated route method
      # calls are provided by `ROUTES`. This method will return the
      # first route method name (Ruby symbol) that has matching URI
      # regular expression. If an HTTP method is not supported, or
      # there is not a matching regular expression, `nil` will be
      # returned.
      #
      # @return [Symbol]
      def determine_route_method
        if ROUTES.has_key?(@http_request_method)
          route = ROUTES[@http_request_method].detect do |route|
            @http_request_uri =~ route[0]
          end
          route ? route[1] : nil
        else
          nil
        end
      end

      # Route the HTTP request. OPTIONS HTTP requests will always
      # return a `200` with no response content. This method uses
      # `determine_route_method()` to determine the symbolized route
      # method to send/call. If a route method does not exist for the
      # HTTP request method and URI, this method uses
      # `allowed_http_methods?()` to determine if a 404 (Not Found) or
      # 405 (Method Not Allowed) HTTP response should be used.
      def route_request
        if @http_request_method == OPTIONS_METHOD
          respond
        else
          route_method = determine_route_method
          if route_method
            send(route_method)
          else
            allowed_http_methods = allowed_http_methods?
            if allowed_http_methods.empty?
              not_found!
            else
              method_not_allowed!(allowed_http_methods)
            end
          end
        end
      end

      # Process a HTTP request. Log the request, parse the HTTP query
      # parameters, create the HTTP response object, set the cors HTTP
      # response headers, determine if the request is authorized,
      # determine if the API is connected to Redis and the Transport,
      # and then route the HTTP request (responding to the request).
      # This method is called by EM HTTP Server when handling a new
      # connection.
      def process_http_request
        log_request
        parse_parameters
        create_response
        set_headers
        if authorized?
          if connected?
            route_request
          else
            error!
          end
        else
          unauthorized!
        end
      end

      # Catch uncaught/unexpected errors, log them, and attempt to
      # respond with a `500` (Internal Server Error) HTTP response.
      # This method is called by EM HTTP Server.
      #
      # @param error [Object]
      def http_request_errback(error)
        @logger.error("unexpected api error", {
          :error => error.to_s,
          :backtrace => error.backtrace.join("\n")
        })
        error! rescue nil
      end
    end
  end
end
