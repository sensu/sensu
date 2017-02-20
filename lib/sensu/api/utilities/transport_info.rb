module Sensu
  module API
    module Utilities
      module TransportInfo
        # Retreive the Sensu Transport info, if the API is connected
        # to it, keepalive messages and consumers, and results
        # messages and consumers.
        #
        # @yield [Hash] passes Transport info to the callback/block.
        def transport_info
          info = {
            :name => @settings[:transport][:name],
            :keepalives => {
              :messages => nil,
              :consumers => nil
            },
            :results => {
              :messages => nil,
              :consumers => nil
            },
            :connected => false
          }
          if @transport.connected?
            @transport.stats("keepalives") do |stats|
              info[:keepalives] = stats
              if @transport.connected?
                @transport.stats("results") do |stats|
                  info[:results] = stats
                  info[:connected] = @transport.connected?
                  yield(info)
                end
              else
                yield(info)
              end
            end
          else
            yield(info)
          end
        end
      end
    end
  end
end
