module Sensu
  module API
    module Utilities
      module ServersInfo
        # Retreive the Sensu servers info.
        #
        # @yield [Hash] passes servers info to the callback/block.
        def servers_info
          info = []
          if @redis.connected?
            @redis.smembers("servers") do |servers|
              unless servers.empty?
                servers.each_with_index do |server_id, index|
                  @redis.get("server:#{server_id}") do |server_json|
                    unless server_json.nil?
                      info << Sensu::JSON.load(server_json)
                    else
                      @redis.srem("servers", server_id)
                    end
                    if index == servers.length - 1
                      yield(info)
                    end
                  end
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
