require "sensu/api/routes/info"
require "sensu/api/routes/health"

module Sensu
  module API
    module Routes
      include Info
      include Health
    end
  end
end
