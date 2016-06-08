require "sensu/api/routes/info"
require "sensu/api/routes/health"
require "sensu/api/routes/clients"
require "sensu/api/routes/checks"
require "sensu/api/routes/request"

module Sensu
  module API
    module Routes
      include Info
      include Health
      include Clients
      include Checks
      include Request
    end
  end
end
