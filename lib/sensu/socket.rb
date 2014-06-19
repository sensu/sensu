module Sensu
  class Socket < EM::Connection
    attr_accessor :logger, :settings, :transport, :reply

    def respond(data)
      unless @reply == false
        send_data(data)
      end
    end

    def post_init
      @data = ""
      @expected_data_len = nil
      @first_packet = true
    end

    def receive_data(data)
      if data =~ /[\x80-\xff]/n
        @logger.warn('socket received non-ascii characters')
        respond('invalid')
      elsif data.strip == 'ping'
        @logger.debug('socket received ping')
        respond('pong')
      else
        if @first_packet
          if data =~ /^(\d+)\n/n
            @expected_data_len = $1.to_i
            @logger.debug("expecting data of length #{@expected_data_len}")
            data = data[data.index("\n")+1..-1]
          end
          @first_packet = false
        end
        if @expected_data_len and @data.length < @expected_data_len
          @data += data
          # Check whether this last packet completes the data
          if @data.length < @expected_data_len
            @logger.debug("expecting #{@expected_data_len - @data.length} bytes more")
            return
          end
          # Remove any extra bytes the client might have sent
          @data = @data[0..@expected_data_len-1]
          @logger.debug("received data of expected length #{@expected_data_len}")
        end
        # Handle the existing behaviour
        if @expected_data_len.nil?
          @data = data
        end
        @logger.debug('socket received data', {
          :data => @data
        })
        begin
          check = MultiJson.load(@data)
          check[:issued] = Time.now.to_i
          check[:status] ||= 0
          validates = [
            check[:name] =~ /^[\w\.-]+$/,
            check[:output].is_a?(String),
            check[:status].is_a?(Integer)
          ].all?
          if validates
            payload = {
              :client => @settings[:client][:name],
              :check => check
            }
            @logger.info('publishing check result', {
              :payload => payload
            })
            @transport.publish(:direct, 'results', MultiJson.dump(payload))
            respond('ok')
          else
            @logger.warn('invalid check result', {
              :check => check
            })
            respond('invalid')
          end
        rescue MultiJson::ParseError => error
          @logger.warn('check result must be valid json', {
            :data => @data,
            :error => error.to_s
          })
          respond('invalid')
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
