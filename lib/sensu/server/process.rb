require "sensu/daemon"
require "sensu/server/filter"
require "sensu/server/handle"

module Sensu
  module Server
    class Process
      include Daemon
      include Filter
      include Handle

      attr_reader :is_master, :handlers_in_progress_count

      def self.run(options={})
        server = self.new(options)
        EM::run do
          server.start
          server.setup_signal_traps
        end
      end

      def initialize(options={})
        super
        @is_master = false
        @timers[:master] = Array.new
        @handlers_in_progress_count = 0
      end
    end
  end
end
