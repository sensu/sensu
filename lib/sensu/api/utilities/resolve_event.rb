require "sensu/api/utilities/publish_check_result"

module Sensu
  module API
    module Utilities
      module ResolveEvent
        include PublishCheckResult

        # Resolve an event. This method publishes a check result with
        # a check status of `0` (OK) to resolve the event. The
        # published check result uses `force_resolve` to ensure the
        # event is resolved and removed from the registry, even if the
        # current event has an event action of `flapping` etc.
        #
        # @param event_json [String] JSON formatted event data.
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
