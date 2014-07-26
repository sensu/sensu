module Sensu
  class Socket < EM::Connection
    attr_accessor :logger, :settings, :transport, :reply

    def respond(data)
      unless @reply == false
        send_data(data)
      end
    end

    def receive_data(data)
      if data.bytes.find { |char| char > 0x80 }
        @logger.warn('socket received non-ascii characters')
        respond('invalid')
      elsif data.strip == 'ping'
        @logger.debug('socket received ping')
        respond('pong')
      else
        @logger.debug('socket received data', {
          :data => data
        })
        begin
          check = MultiJson.load(data)
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
            :data => data,
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
