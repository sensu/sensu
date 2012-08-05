module Sensu
  class Socket < EM::Connection
    attr_accessor :protocol, :logger, :settings, :amq

    def reply(data)
      if @protocol == :tcp
        send_data(data)
      end
    end

    def receive_data(data)
      if data.strip == 'ping'
        @logger.debug('socket received ping')
        reply('pong')
      else
        @logger.debug('socket received data', {
          :data => data
        })
        begin
          check = JSON.parse(data, :symbolize_names => true)
          validates = [:name, :output].all? do |key|
            check[key].is_a?(String)
          end
          check[:issued] = Time.now.to_i
          check[:status] ||= 0
          if validates && check[:status].is_a?(Integer)
            payload = {
              :client => @settings[:client][:name],
              :check => check
            }
            @logger.info('publishing check result', {
              :payload => payload
            })
            @amq.queue('results').publish(payload.to_json)
            reply('ok')
          else
            @logger.warn('invalid check result', {
              :check => check
            })
            reply('invalid')
          end
        rescue JSON::ParserError => error
          @logger.warn('check result must be valid json', {
            :data => data,
            :error => error.to_s
          })
          reply('invalid')
        end
      end
    end
  end
end
