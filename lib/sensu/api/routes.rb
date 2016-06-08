require "sensu/api/routes/info"
require "sensu/api/routes/health"
require "sensu/api/routes/clients"
require "sensu/api/routes/checks"
require "sensu/api/routes/request"
require "sensu/api/routes/events"

module Sensu
  module API
    module Routes
      include Info
      include Health
      include Clients
      include Checks
      include Request
      include Events
    end
  end
end
