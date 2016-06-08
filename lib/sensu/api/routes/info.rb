module Sensu
  module API
    module Routes
      module Info
        GET_INFO_URI = "/info".freeze

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

        def get_info
          transport_info do |info|
            @response_content = {
              :sensu => {
                :version => VERSION
              },
              :transport => info,
              :redis => {
                :connected => @redis.connected?
              }
            }
            respond
          end
        end
      end
    end
  end
end
