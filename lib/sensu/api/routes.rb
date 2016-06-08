require "sensu/api/routes/info"
require "sensu/api/routes/health"
require "sensu/api/routes/clients"
require "sensu/api/routes/checks"
require "sensu/api/routes/request"
require "sensu/api/routes/events"
require "sensu/api/routes/resolve"
require "sensu/api/routes/aggregates"

module Sensu
  module API
    module Routes
      include Info
      include Health
      include Clients
      include Checks
      include Request
      include Events
      include Resolve
      include Aggregates
    end
  end
end
