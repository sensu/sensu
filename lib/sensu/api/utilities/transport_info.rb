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
            :keepalives => {
              :messages => nil,
              :consumers => nil
            },
            :results => {
              :messages => nil,
              :consumers => nil
            },
            :connected => @transport.connected?
          }
          if @transport.connected?
            @transport.stats("keepalives") do |stats|
              info[:keepalives] = stats
              @transport.stats("results") do |stats|
                info[:results] = stats
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
