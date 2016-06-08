require "sensu/api/routes/info"
require "sensu/api/routes/health"
require "sensu/api/routes/clients"

module Sensu
  module API
    module Routes
      include Info
      include Health
      include Clients
    end
  end
end
