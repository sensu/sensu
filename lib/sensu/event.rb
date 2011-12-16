module Sensu
  class Event
    self.transform_to_graphite(event) do
      begin
        metrics = JSON.parse(event.check.output)
      rescue JSON::ParserError => error
      end

      if metrics.is_a?(String)
        metric = metrics.split(' ')
        metric[0] = ['sensu', event.client.name, event.check.name, metric[0]].join('.')
      elsif metrics.is_a?(Array)
      end
    end
  end
end
