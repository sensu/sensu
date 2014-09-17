module Sensu
  # EventMachine connection handler for the Sensu client's
  # local-socket protocol.
  #
  # Sensu client listens on localhost port 3030 (by default) for UDP
  # and TCP traffic. This allows software running on the host to push
  # check results (that may contain metrics) into Sensu from the edge,
  # without needing to know anything about Sensu's internal
  # implementation.
  #
  # The local-socket protocol accepts only 7-bit ASCII-encoded data.
  #
  # Although the Sensu client accepts UDP and TCP traffic, you must be
  # aware the UDP protocol is limited in the extreme. Any data you
  # send over UDP must fit in a single datagram and you will not
  # receive a response. You will have no idea of whether your data was
  # accepted or rejected.
  #
  # == UDP Protocol ==
  #
  # If the socket receives a message containing whitespace and the
  # string +'ping'+, it will ignore it.
  #
  # The socket assumes all other messages will contain a single,
  # complete, JSON hash. The hash must be a valid JSON result.
  # Deserialization failures will be logged at the WARN level by the
  # Sensu client, but the sender of the invalid data will not be
  # notified.
  #
  # == TCP Protocol ==
  #
  # If the socket receives a message containing whitespace and the
  # string +'ping'+, it will respond with the message +'pong'+.
  #
  # The socket assumes any other stream will be a single, complete,
  # JSON hash. A deserialization failure will be logged at the WARN
  # level by the Sensu client and respond with the message
  # +'invalid'+. An +'ok'+ response indicates the Sensu client
  # successfully received the JSON hash and will publish the result.
  #
  # Streams can be of any length. The local-socket protocol does not
  # require any headers, instead the socket tries to parse everything
  # it has been sent each time a chunk of data arrives. Once the JSON
  # parses successfully, the Sensu client publishes the result. After
  # +WATCHDOG_DELAY+ (default is 500 msec) since the most recent chunk
  # of data showed up, the agent will give up on receiving any more
  # from the client, and instead respond +'invalid'+ and close the
  # connection.
  class Socket < EM::Connection
    class DataError < StandardError; end

    attr_accessor :logger, :settings, :transport, :reply

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
    # chunks of data in this mode because the connection is being
    # closed.
    MODE_REJECT = :REJECT

    # Initialize instance variables that will be used throughout the
    # lifetime of the connection.
    def post_init
      @data_buffer = ''
      @parse_errors = []
      @watchdog = nil
      @mode = MODE_ACCEPT
    end

    # Send a response to sender, if possible.
    #
    # @param [String] data to send as a response.
    def respond(data)
      unless @reply == false
        send_data(data)
      end
    end

    # Start or reset the connection watchdog.
    def reset_watchdog
      if @watchdog
        @watchdog.cancel
      end
      @watchdog = EM::Timer.new(WATCHDOG_DELAY) do
        @mode = MODE_REJECT
        @logger.warn('discarding data buffer for sender and closing connection', {
          :data_buffer => @data_buffer,
          :parse_errors => @parse_errors
        })
        respond('invalid')
        close_connection_after_writing
      end
    end

    # This method is called whenever data is received. For a UDP
    # "session", this gets called once. For a TCP session, gets called
    # one or more times.
    #
    # @param [String] data received from the sender.
    def receive_data(data)
      if EM.reactor_running?
        reset_watchdog
      end
      unless @mode == MODE_REJECT
        @data_buffer << data
        begin
          process_data(@data_buffer)
        rescue DataError => error
          @logger.warn('failed to process data buffer for sender', {
            :data_buffer => @data_buffer,
            :error => error.to_s
          })
          respond('invalid')
        end
      end
    end

    # Validate a check result.
    #
    # @param [Hash] check result to validate.
    def validate_check_result(check)
      unless check[:name] =~ /^[\w\.-]+$/
        raise DataError, 'check name must be a string and cannot contain spaces or special characters'
      end
      unless check[:output].is_a?(String)
        raise DataError, 'check output must be a string'
      end
      unless check[:status].is_a?(Integer)
        raise DataError, 'check status must be an integer'
      end
    end

    # Publish a check result to the Sensu transport and respond to the
    # sender, with the message +'ok'+.
    #
    # @param [Hash] check result.
    def publish_check_result(check)
      payload = {
        :client => @settings[:client][:name],
        :check => check.merge(:issued => Time.now.to_i)
      }
      @logger.info('publishing check result', {
        :payload => payload
      })
      @transport.publish(:direct, 'results', MultiJson.dump(payload))
    end

    # Process a check result. Set check result attribute defaults,
    # validate the check result, publish the check result to the Sensu
    # transport, and reply to the sender with the message +'ok'+.
    #
    # @param [String] check result to be validated and published.
    # @raise [DataError] if +check+ is invalid.
    def process_check_result(check)
      check[:status] ||= 0
      validate_check_result(check)
      publish_check_result(check)
      respond('ok')
    end

    # Process data, parse and validate it. Parsing errors are
    # recorded, so the watchdog can log them when it is triggered.
    #
    # @param [String] data to be processed.
    # @raise [DataError] when the data contains non-ASCII characters.
    def process_data(data)
      if data.bytes.find { |char| char > 0x80 }
        raise DataError, 'socket received non-ascii characters'
      elsif data.strip == 'ping'
        @logger.debug('socket received ping')
        respond('pong')
      else
        @logger.debug('socket received data', {
          :data => data
        })
        begin
          check = MultiJson.load(data)
          if @watchdog
            @watchdog.cancel
          end
          process_check_result(check)
        rescue MultiJson::ParseError => error
          @parse_errors << error.to_s
        end
      end
    end
  end

  class SocketHandler < EM::Connection
    attr_accessor :on_success, :on_error

    def connection_completed
      @connected_at = Time.now.to_f
      @inactivity_timeout = comm_inactivity_timeout
    end

    def unbind
      if @connected_at
        elapsed_time = Time.now.to_f - @connected_at
        if elapsed_time >= @inactivity_timeout
          @on_error.call('socket inactivity timeout')
        else
          @on_success.call('wrote to socket')
        end
      else
        @on_error.call('failed to connect to socket')
      end
    end
  end
end
