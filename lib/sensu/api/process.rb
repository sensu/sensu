require "sensu/daemon"
require "sensu/api/http_handler"

module Sensu
  module API
    class Process
      include Daemon

      # Create an instance of the Sensu API process, setup the Redis
      # and Transport connections, start the API HTTP server, set up
      # API process signal traps (for stopping), within the
      # EventMachine event loop.
      #
      # @param options [Hash]
      def self.run(options={})
        api = self.new(options)
        EM::run do
          api.start
          api.setup_signal_traps
        end
      end

      # Setup connections to redis and transport
      #
      # @yield [Object] a callback/block to be called after redis and
      #   transport connections have been established.
      def setup_connections
        setup_redis do |redis|
          setup_transport do |transport|
            yield if block_given?
          end
        end
      end

      # Start the API HTTP server. This method sets `@http_server`.
      #
      # @param bind [String] address to listen on.
      # @param port [Integer] to listen on.
      def start_http_server(bind, port)
        @logger.info("api listening", {
          :protocol => "http",
          :bind => bind,
          :port => port
        })
        @http_server = EM::start_server(bind, port, HTTPHandler) do |handler|
          handler.logger = @logger
          handler.settings = @settings
          handler.redis = @redis
          handler.transport = @transport
        end
      end

      # Start the Sensu API HTTP server. This method sets the service
      # state to `:running`.
      def start
        api = @settings[:api] || {}
        bind = api[:bind] || "0.0.0.0"
        port = api[:port] || 4567
        setup_connections do
          start_http_server(bind, port)
          yield if block_given?
        end
        super
      end

      # Stop the Sensu API process. This method stops the HTTP server,
      # closes the Redis and transport connections, sets the service
      # state to `:stopped`, and stops the EventMachine event loop.
      def stop
        @logger.warn("stopping")
        EM::stop_server(@http_server)
        @redis.close if @redis
        @transport.close if @transport
        super
      end

      # Create an instance of the Sensu API with initialized
      # connections for running test specs.
      #
      # @param options [Hash]
      def self.test(options={})
        api = self.new(options)
        api.start do
          yield
        end
      end
    end
  end
end
