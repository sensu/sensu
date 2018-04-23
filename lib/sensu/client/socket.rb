require "sensu/json"
require "sensu/client/utils"

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
    class Socket < EM::Connection
      include CheckUtils

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
        @parse_error = nil
        @watchdog = nil
        @mode = MODE_ACCEPT
      end

      # Send a response to the sender, close the
      # connection, and call post_init().
      #
      # @param [String] data to send as a response.
      def respond(data)
        if @protocol == :tcp
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
          respond("invalid")
        end
      end

      # Parse one or more JSON check results. For UDP, immediately
      # raise a parser error. For TCP, record parser errors, so the
      # connection +watchdog+ can report them.
      #
      # @param [String] data to parse for a check result.
      def parse_check_result(data)
        begin
          object = Sensu::JSON.load(data)
          cancel_watchdog
          if object.is_a?(Array)
            object.each do |check|
              process_check_result(check)
            end
          else
            process_check_result(object)
          end
          respond("ok")
        rescue Sensu::JSON::ParseError, ArgumentError => error
          if @protocol == :tcp
            @parse_error = error.to_s
          else
            raise error
          end
        end
      end

      # Process the data received. This method validates the data
      # encoding, provides ping/pong functionality, and passes potential
      # check results on for further processing.
      #
      # @param [String] data to be processed.
      def process_data(data)
        if data.strip == PING_REQUEST
          @logger.debug("socket received ping")
          respond("pong")
        else
          @logger.debug("socket received data", :data => data)
          unless valid_utf8?(data)
            @logger.warn("data from socket is not a valid UTF-8 sequence, processing it anyways", :data => data)
          end
          begin
            parse_check_result(data)
          rescue => error
            @logger.error("failed to process check result from socket", {
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
          case @protocol
          when :udp
            process_data(data)
          when :tcp
            if EM::reactor_running?
              reset_watchdog
            end
            @data_buffer << data
            process_data(@data_buffer)
          end
        end
      end
    end
  end
end
