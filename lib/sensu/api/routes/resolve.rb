require "sensu/api/utilities/resolve_event"

module Sensu
  module API
    module Routes
      module Resolve
        include Utilities::ResolveEvent

        RESOLVE_URI = /^\/resolve$/

        # POST /resolve
        def post_resolve
          rules = {
            :client => {:type => String, :nil_ok => false},
            :check => {:type => String, :nil_ok => false}
          }
          read_data(rules) do |data|
            @redis.hgetall("events:#{data[:client]}") do |events|
              if events.include?(data[:check])
                resolve_event(events[data[:check]])
                @response_content = {:issued => Time.now.to_i}
                accepted!
              else
                not_found!
              end
            end
          end
        end
      end
    end
  end
end
