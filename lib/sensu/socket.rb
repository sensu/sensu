module Sensu
  class Socket < EM::Connection

    class DataError < StandardError; end

    attr_accessor :logger, :settings, :transport, :reply

    def respond(data)
      unless @reply == false
        send_data(data)
      end
    end

    def receive_data(data)
      begin
        process_data(data)
      rescue DataError => exception
        @logger.warn(exception.to_s)
        respond('invalid')
      end
    end

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
        process_json(data)
        respond('ok')
      end
    end

    def process_json(data)
      check = self.class.load_json(data)

      check[:status] ||= 0

      self.class.validate_check_data(check)

      publish_check_data(check)
    end

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

    def self.load_json(data)
      begin
        MultiJson.load(data)
      rescue MultiJson::ParseError => error
        fail(DataError, "check result is not valid json: error: #{error.to_s}")
      end
    end

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
