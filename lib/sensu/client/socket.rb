require "sensu/json"
$HTTP_PARSER_AVAILABLE = true
begin
  require "json"
  require "http-parser"
rescue LoadError
  $HTTP_PARSER_AVAILABLE = false
end

module Sensu
  module Client
    # EventMachine connection handler for the Sensu client"s socket.
    #
    # The Sensu client listens on localhost, port 3030 (by default), for
    # UDP and TCP traffic. This allows software running on the host to
    # push check results (that may contain metrics) into Sensu, without
    # needing to know anything about Sensu"s internal implementation.
    #
    # The socket only accepts 7-bit ASCII-encoded data.
    #
    # Although the Sensu client accepts UDP and TCP traffic, you must be
    # aware of the UDP protocol limitations. Any data you send over UDP
    # must fit in a single datagram and you will not receive a response
    # (no confirmation).
    #
    # == UDP Protocol ==
    #
    # If the socket receives a message containing whitespace and the
    # string +"ping"+, it will ignore it.
    #
    # The socket assumes all other messages will contain a single,
    # complete, JSON hash. The hash must be a valid JSON check result.
    # Deserialization failures will be logged at the ERROR level by the
    # Sensu client, but the sender of the invalid data will not be
    # notified.
    #
    # == TCP Protocol ==
    #
    # If the socket receives a message containing whitespace and the
    # string +"ping"+, it will respond with the message +"pong"+.
    #
    # The socket assumes any other stream will be a single, complete,
    # JSON hash. A deserialization failure will be logged at the WARN
    # level by the Sensu client and respond with the message
    # +"invalid"+. An +"ok"+ response indicates the Sensu client
    # successfully received the JSON hash and will publish the check
    # result.
    #
    # Streams can be of any length. The socket protocol does not require
    # any headers, instead the socket tries to parse everything it has
    # been sent each time a chunk of data arrives. Once the JSON parses
    # successfully, the Sensu client publishes the result. After
    # +WATCHDOG_DELAY+ (default is 500 msec) since the most recent chunk
    # of data was received, the agent will give up on the sender, and
    # instead respond +"invalid"+ and close the connection.
    #
    # == HTTP Protocol ==
    #
    # This is naturally implemented on top of the TCP protocol and
    # requires sending an appropiate HTTP request. All requests
    # will be responded with an appropiate HTTP response code and
    # json body with a 'response' member typically set to 'ok' but
    # that depends on the URL requested and whether the operation
    # requested was successful or not.
    # The following urls are available:
    # /ping
    #   This endpoint will simply return a 200 OK with a pong response
    # /check
    #   This endpoint must receive an application/json body with the
    #   check information.
    # Requesting an invalid URL returns 404, as it should be expected.
    class Socket < EM::Connection
      class DataError < StandardError; end

      attr_accessor :logger, :settings, :transport, :protocol

      # The number of seconds that may elapse between chunks of data
      # from a sender before it is considered dead, and the connection
      # is close.
      WATCHDOG_DELAY = 0.5

      #
      # Sensu::Socket operating mode enum.
      #

      # ACCEPT mode. Append chunks of data to a buffer and test to see
      # whether the buffer contents are valid JSON.
      MODE_ACCEPT = :ACCEPT

      # REJECT mode. No longer receiving data from sender. Discard
      # chunks of data in this mode, the connection is being closed.
      MODE_REJECT = :REJECT

      # PING request string, identifying a connection ping request.
      PING_REQUEST = "ping".freeze

      # Initialize instance variables that will be used throughout the
      # lifetime of the connection. This method is called when the
      # network connection has been established, and immediately after
      # responding to a sender.
      def post_init
        @protocol ||= :tcp
        @data_buffer = ""
        @data_chunks = 0
        @parse_error = nil
        @watchdog = nil
        @mode = MODE_ACCEPT
        @http_parser = nil
        @http_req = nil
        @http_req_done = false
        @http_url = ""
        @http_headers = {}
        @http_body = ""
      end

      # Initialize the http parser
      #
      # @param [HttpParser::Parser] The parser to initialize
      def http_init_parser(parser)
        current_header = ""
        parsing_header = false

        parser.on_message_begin do |inst|
          @logger.debug("HTTP request started")
        end

        parser.on_message_complete do |inst|
          @logger.debug("HTTP request completed")
          @http_req_done = true
        end

        parser.on_headers_complete do |inst|
          @logger.debug("HTTP headers done")
          if not @http_headers.key?("CONTENT-LENGTH")
            @logger.warn("No content-length specified in HTTP request")
            @logger.warn("HTTP headers: ", @http_headers)
          end
        end

        parser.on_url do |inst, data|
          @logger.debug("HTTP URL chunk parsed: #{data}")
          @http_url << data
        end

        parser.on_header_field do |inst, data|
          @logger.debug("HTTP Header name chunk parsed: #{data}")
          if not parsing_header
            parsing_header = true
            current_header = data
          else
            current_header << data
          end
        end

        parser.on_header_value do |inst, data|
          @logger.debug("HTTP Header #{current_header} value chunk parsed: #{data}")
          if parsing_header
            parsing_header = false
            @http_headers[current_header.upcase] = data
            current_header = data
          else
            @http_headers[current_header.upcase] << data
          end
        end

        parser.on_body do |inst, data|
          @logger.debug("HTTP Body chunk parsed: #{data}")
          @http_body << data
          @logger.debug("HTTP Body length is #{@http_body.length}, content-length is #{@http_headers['CONTENT-LENGTH']}")
          if @http_body.length == @http_headers["CONTENT-LENGTH"].to_i
            @logger.debug("Done receiving HTTP body of length #{@http_headers['CONTENT-LENGTH']}")
            @http_req_done = true
          end
        end
      end

      # Send a response to the sender, close the
      # connection, and call post_init().
      #
      # @param [String] data to send as a response.
      def respond(data)
        if @protocol == :tcp
          @logger.debug("Responding to request", :data => data)
          send_data(data)
          close_connection_after_writing
        end
        post_init
      end

      # Cancel the current connection watchdog.
      def cancel_watchdog
        if @watchdog
          @watchdog.cancel
        end
      end

      # Reset (or start) the connection watchdog.
      def reset_watchdog
        cancel_watchdog
        @watchdog = EM::Timer.new(WATCHDOG_DELAY) do
          @mode = MODE_REJECT
          @logger.warn("discarding data buffer for sender and closing connection", {
            :data => @data_buffer,
            :parse_error => @parse_error
          })
          if @http_parser
            http_respond("Timed out", 408, "Timed out waiting for all the request")
          else
            respond("invalid")
          end
        end
      end

      # Validate check result attributes.
      #
      # @param [Hash] check result to validate.
      def validate_check_result(check)
        unless check[:name] =~ /\A[\w\.-]+\z/
          raise DataError, "check name must be a string and cannot contain spaces or special characters"
        end
        unless check[:source].nil? || check[:source] =~ /\A[\w\.-]+\z/
          raise DataError, "check source must be a string and cannot contain spaces or special characters"
        end
        unless check[:output].is_a?(String)
          raise DataError, "check output must be a string"
        end
        unless check[:status].is_a?(Integer)
          raise DataError, "check status must be an integer"
        end
        unless check[:executed].is_a?(Integer)
          raise DataError, "check executed timestamp must be an integer"
        end
        unless check[:ttl].nil? || (check[:ttl].is_a?(Integer) && check[:ttl] > 0)
          raise DataError, "check ttl must be an integer greater than 0"
        end
      end

      # Publish a check result to the Sensu transport.
      #
      # @param [Hash] check result.
      def publish_check_result(check)
        payload = {
          :client => @settings[:client][:name],
          :check => check.merge(:issued => Time.now.to_i)
        }
        payload[:signature] = @settings[:client][:signature] if @settings[:client][:signature]
        @logger.info("publishing check result", :payload => payload)
        @transport.publish(:direct, "results", Sensu::JSON.dump(payload)) do |info|
          if info[:error]
            @logger.error("failed to publish check result", {
              :payload => payload,
              :error => info[:error].to_s
            })
            raise IOError, info[:error].to_s
          end
        end
      end

      # Process a check result. Set check result attribute defaults,
      # validate the attributes, publish the check result to the Sensu
      # transport, and respond to the sender with the message +"ok"+.
      #
      # @param [Hash] check result to be validated and published.
      # @raise [DataError] if +check+ is invalid.
      def process_check_result(check)
        check[:status] ||= 0
        check[:executed] ||= Time.now.to_i
        validate_check_result(check)
        publish_check_result(check)
        if @http_parser
          http_respond("ok", 200, "Check Accepted")
        else
          respond("ok")
        end
      end

      # Parse a JSON check result. For UDP, immediately raise a parser
      # error. For TCP, record parser errors, so the connection
      # +watchdog+ can report them.
      #
      # @param [String] data to parse for a check result.
      def parse_check_result(data)
        begin
          check = Sensu::JSON.load(data)
          cancel_watchdog
          process_check_result(check)
        rescue Sensu::JSON::ParseError, ArgumentError => error
          # HTTP data is delivered is parsed only once, if it's invalid
          # no point in waiting for more
          if @protocol == :tcp and not @http_parser
            @parse_error = error.to_s
          else
            raise error
          end
        end
      end

      # Send an HTTP response
      #
      # @param [String] response string to include in the json reply
      # @param [Int] code to use in the HTTP response
      # @param [String] message to use in the HTTP response
      def http_respond(response, code, message)
        response_data = case response
                          when Hash then response.to_json
                          when String then {
                            :response => response
                          }.to_json
                        end
        http_response = [
          "HTTP/1.1 #{code} #{message}",
          "Content-Type: application/json",
          "Content-Length: #{response_data.length}",
          "Connection: close\r\n",
          response_data
        ].join("\r\n")
        respond(http_response)
      end

      # Route http request to the proper handler
      # If request urls actually grow we can put a nice
      # hash-based lookup here to call the proper handler
      # instead of hard-coding the handlers
      #
      # @param [String] url requested
      # @param [String] headers
      # @param [String] body
      def route_http_req(url, headers, body)
        if url == '/ping'
          @logger.debug("http received ping")
          http_respond("pong", 200, "Pong!")
        elsif url == '/settings'
          @logger.debug("settings request", @settings.to_hash)
          http_respond(@settings.to_hash, 200, "OK")
        elsif url == '/check'
          if headers['CONTENT-TYPE'].include? 'json'
            begin
              parse_check_result(body)
            rescue Sensu::JSON::ParseError, ArgumentError => error
              @logger.error("failed to parse check result", {
                :data => body,
                :error => error.to_s
              })
              http_respond("Error parsing check result: #{error.to_s}", 400, "Bad Request")
            rescue IOError => error
              @logger.error("failed to process check result", {
                :data => body,
                :error => error.to_s
              })
              http_respond("IO error processing check result: #{error.to_s}", 504, "Transport Disconnected")
            rescue => error
              @logger.error("Failed to process check result from http payload", {
                :data => body,
                :error => error.to_s
              })
              http_respond("Error when processing check: #{error.to_s}", 500, "Internal Server Error")
            end
          else
            @logger.warn("HTTP request does not include json content type")
            http_respond("Content-type must be application/json", 415, "Unsupported Media Type")
          end
        else
            http_respond("Invalid URL provided", 404, "Not Found")
        end
      end

      # Process http data chunk
      # If the http request is finished it will process the request
      # according to the requested url and payload
      #
      # @param [String] data chunk to be processed.
      def process_http_data(data)
        @logger.debug("HTTP chunk received", {:http_parser => @http_parser, :data => data})
        if not $HTTP_PARSER_AVAILABLE
          http_respond("No http parser available", 501, "Not Implemented")
        else
          if not @http_parser
            # Initialize the parser and request objects
            @http_parser = HttpParser::Parser.new(&method(:http_init_parser))
            @http_req = HttpParser::Parser.new_instance do |inst|
              inst.type = :request
            end
          end
          # Parse this chunk of data
          @http_parser.parse(@http_req, data)
          # If the request is done, route it
          if @http_req_done
            route_http_req(@http_url, @http_headers, @http_body)
          end
        end
      end

      # Process the data received.
      # This method determines the type of request (raw or http)
      # and processes it accordingly.
      #
      # @param [String] data chunk to be processed.
      # @param [String] buffer of collected data so far for this connection
      def process_data(data, data_buffer)
        @logger.debug("Processing data chunk number #{@data_chunks}: ", {:data => data})
        # Determine if this is an http request or a raw udp/tcp request
        # we assume the only raw-request supported other than json check data
        # are 'ping' requests.
        if @data_chunks == 1 and data.strip == PING_REQUEST
          @logger.debug("socket received raw ping")
          respond("pong")
        elsif @http_parser or (@data_chunks == 1 and data.strip[0] != '{')
          process_http_data(data)
        else
          # Not a raw ping, not an http request, better be valid json!
          unless valid_utf8?(data)
            @logger.warn("data from socket is not a valid UTF-8 sequence, processing it anyways", :data => data)
          end
          @logger.debug("Processing raw check data", {:data => data_buffer})
          begin
            parse_check_result(data_buffer)
          rescue => error
            @logger.error("failed to process raw check result from socket", {
              :data => data,
              :error => error.to_s
            })
            respond("invalid")
          end
        end
      end

      # Tests if the argument (data) is a valid UTF-8 sequence.
      #
      # @param [String] data to be tested.
      def valid_utf8?(data)
        utf8_string_pattern = /\A([\x00-\x7f]|
                                  [\xc2-\xdf][\x80-\xbf]|
                                  \xe0[\xa0-\xbf][\x80-\xbf]|
                                  [\xe1-\xef][\x80-\xbf]{2}|
                                  \xf0[\x90-\xbf][\x80-\xbf]{2}|
                                  [\xf1-\xf7][\x80-\xbf]{3})*\z/nx
        data = data.force_encoding('BINARY') if data.respond_to?(:force_encoding)
        return data =~ utf8_string_pattern
      end

      # This method is called whenever data is received. For UDP, it
      # will only be called once, the original data length can be
      # expected. For TCP, this method may be called several times, data
      # received is buffered. TCP connections require a +watchdog+.
      #
      # @param [String] data received from the sender.
      def receive_data(data)
        unless @mode == MODE_REJECT
          @data_chunks += 1
          @data_buffer << data
          case @protocol
          when :udp
            process_data(data, @data_buffer)
          when :tcp
            if EM::reactor_running?
              reset_watchdog
            end
            process_data(data, @data_buffer)
          end
        end
      end
    end
  end
end
