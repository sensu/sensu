require "sensu/daemon"
require "sensu/api/http_handler"

gem "sinatra", "1.4.6"
gem "async_sinatra", "1.2.0"

require "sinatra/async"

module Sensu
  module API
    class Process < Sinatra::Base
      register Sinatra::Async

      class << self
        include Daemon

        def run(options={})
          bootstrap(options)
          setup_process(options)
          EM::run do
            setup_connections
            setup_signal_traps
            start
          end
        end

        def setup_connections
          setup_redis do |redis|
            setup_transport do |transport|
              yield if block_given?
            end
          end
        end

        def bootstrap(options)
          setup_logger(options)
          load_settings(options)
        end

        def start
          @http_server = EM::start_server("0.0.0.0", 4567, HTTPHandler) do |handler|
            handler.logger = @logger
            handler.settings = @settings
            handler.redis = @redis
            handler.transport = @transport
          end
          super
        end

        def stop
          @logger.warn("stopping")
          EM.stop_server(@http_server)
          @redis.close if @redis
          @transport.close if @transport
          super
        end

        def test(options={})
          bootstrap(options)
          setup_connections do
            start
            yield
          end
        end
      end

      configure do
        disable :protection
        disable :show_exceptions
      end

      not_found do
        ""
      end

      error do
        ""
      end

      helpers do
        def connected?
          if settings.respond_to?(:redis) && settings.respond_to?(:transport)
            unless ["/info", "/health"].include?(env["REQUEST_PATH"])
              unless settings.redis.connected?
                not_connected!("not connected to redis")
              end
              unless settings.transport.connected?
                not_connected!("not connected to transport")
              end
            end
          else
            not_connected!("redis and transport connections not initialized")
          end
        end

        def error!(body="")
          throw(:halt, [500, body])
        end

        def not_connected!(message)
          error!(Sensu::JSON.dump(:error => message))
        end
      end

      before do
        request_log_line
        content_type "application/json"
        settings.cors.each do |header, value|
          headers["Access-Control-Allow-#{header}"] = value
        end
        connected?
        protected! unless env["REQUEST_METHOD"] == "OPTIONS"
      end

    end
  end
end
