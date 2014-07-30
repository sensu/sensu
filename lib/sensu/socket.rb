module Sensu

  # EventMachine connection handler for the Sensu client's local-agent protocol.
  #
  # Sensu-client listens on localhost port 3030 (by default) for UDP and TCP traffic. This
  # is so that software running on the host can push check results or metrics into sensu
  # from the edge without needing to know anything about sensu's internal implementation.
  #
  # The local-agent protocol accepts only 7-bit ASCII-encoded data.
  #
  # Although Sensu-client accepts UDP and TCP traffic, you must be aware the UDP protocol is limited
  # in the extreme. Any data you send over UDP must fit in a single datagram and you will receive no
  # response at all. You will have no idea of whether your data was accepted or rejected.
  #
  # == UDP Protocol ==
  #
  # If the client sends a message containing whitespace and the string +'ping'+, Sensu will accept it and
  # ignore it.
  #
  # Sensu assumes all other packets will contain a single, complete JSON hash. The hash must be a valid
  # JSON result. Deserialization failures will be logged at the WARN level by sensu-client, but the sender
  # of the invalid data will not be notified.
  #
  # == TCP Protocol ==
  #
  # If the client (i.e., someone else's software) sends the agent (i.e., Sensu-client) a message
  # containing only whitespace and the string +'ping'+, the agent responds back with +'pong'+.
  #
  # Sensu assumes any other stream will be a single, complete, and valid JSON hash. A deserialization failure
  # will be logged at the WARN level by sensu-client and cause an +'invalid'+ response. An +'ok'+ response
  # indicates the agent successfully received the JSON hash and has already passed it on.
  #
  # Streams can be of any length. The agent protocol does not require any headers, instead the agent tries
  # to parse everything it's been sent each time a chunk of data arrives. Once the JSON parses successfully,
  # the agent relays the data. After +WATCHDOG_DELAY+ (normally 500 msec) since the most recent chunk of data
  # showed up, the agent will give up on receiving any more from the client, and instead respond +'invalid'+
  # and close the connection.
  class Socket < EM::Connection

    class DataError < StandardError; end

    attr_accessor :logger, :settings, :transport, :reply

    # How many seconds may elapse between chunks of data coming over the
    # socket before we give up and decide the client is never going to
    # send more data.
    WATCHDOG_DELAY = 0.5

    #
    # Sensu::Socket operating mode enum.
    #

    # ACCEPT mode. We append chunks of data to a running buffer and
    # test to see whether the buffer contents are valid JSON.
    MODE_ACCEPT = :ACCEPT

    # REJECT mode. We have given up on receiving data. We discard
    # arriving data in this mode because we are shutting the socket
    # down.
    MODE_REJECT = :REJECT

    def initialize(*)
      @data_buffer = ''
      @last_parse_error = nil
      @watchdog = nil
      @mode = MODE_ACCEPT
    end

    # Send a response to the client, if possible.
    # @param [String] data the data buffer to reply to the client with.
    def respond(data)
      unless @reply == false
        send_data(data)
      end
    end

    # EventMachine::Connection callback. EM calls this method each time a buffer of data shows up from the client.
    # For a UDP "session" this gets called once. For a TCP session, gets called one or more times.
    # @param [String] data a buffer containing the data the client sent us.
    def receive_data(data)
      reset_watchdog if EventMachine.reactor_running?

      return if @mode == MODE_REJECT

      @data_buffer << data

      begin
        process_data(@data_buffer)
      rescue DataError => exception
        @logger.warn(exception.to_s)
        respond('invalid')
      end
    end

    # Process what the client's sent us so far.
    # @param [String] data all the data to attempt to process.
    # @raise [DataError] when the buffer contains data that is not 7-bit ASCII
    def process_data(data)
      if data.bytes.find { |char| char > 0x80 }
        fail(DataError, 'socket received non-ascii characters')
      elsif data.strip == 'ping'
        @logger.debug('socket received ping')
        respond('pong')
      else
        @logger.debug('socket received data', {
          :data => data
        })

        # See if we've got a complete JSON blob. If we do, forward it on. If we don't, store
        # the exception so the watchdog can log it if it fires.
        begin
          MultiJson.load(data, :symbolize_keys => false)
        rescue MultiJson::ParseError => error
          @last_parse_error = error
        else
          process_json(data)
          @watchdog.cancel if @watchdog
          respond('ok')
        end
      end
    end

    # Process a complete JSON structure.
    # @param [String] data a parseable blob of JSON.
    # @raise [DataError] if +data+ describes an invalid check result.
    def process_json(data)
      check = MultiJson.load(data)

      check[:status] ||= 0

      self.class.validate_check_data(check)

      publish_check_data(check)
    end

    # Publish the check result into Sensu.
    # @param [Hash] check a valid check result.
    def publish_check_data(check)
      payload = {
        :client => @settings[:client][:name],
        :check => check.merge(:issued => Time.now.to_i),
      }

      @logger.info('publishing check result', {
        :payload => payload
      })

      @transport.publish(:direct, 'results', MultiJson.dump(payload))
    end

    # Start or reset the watchdog.
    def reset_watchdog
      @watchdog.cancel if @watchdog
      @watchdog = EventMachine::Timer.new(WATCHDOG_DELAY) do
        @mode = MODE_REJECT

        @logger.warn('giving up on data buffer from client', {
          :data_buffer => @data_buffer,
          :last_parse_error => @last_parse_error.to_s,
        })
        respond('invalid')
        close_connection_after_writing
      end
    end

    # Validate the given check is well-formed.
    # @param [Hash] check the check to validate.
    # @raise [DataError] when a validation fails. The exception's message describes the problem.
    def self.validate_check_data(check)
      #
      # Basic sanity checks.
      #
      fail(DataError, "invalid check name: '#{check[:name]}'") unless check[:name] =~ /^[\w\.-]+$/
      fail(DataError, "check output must be a String, got #{check[:output].class.name} instead") unless check[:output].is_a?(String)

      #
      # Status code validation.
      #
      status_code = check[:status]

      unless status_code.is_a?(Integer)
        fail(DataError, "check status must be an Integer, got #{status_code.class.name} instead") unless status_code.is_a?(Integer)
      end

      unless 0 <= status_code && status_code <= 3
        fail(DataError, "check status must be in {0, 1, 2, 3}, got #{status_code} instead")
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
