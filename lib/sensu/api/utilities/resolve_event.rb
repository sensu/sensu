require "sensu/api/utilities/publish_check_result"

module Sensu
  module API
    module Utilities
      module ResolveEvent
        include PublishCheckResult

        def resolve_event(event_json)
          event = Sensu::JSON.load(event_json)
          check = event[:check].merge(
            :output => "Resolving on request of the API",
            :status => 0,
            :force_resolve => true
          )
          check.delete(:history)
          publish_check_result(event[:client][:name], check)
        end
      end
    end
  end
end
