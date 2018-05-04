gem "em-http-request", "1.1.5"

require "em-http-request"
require "sensu/constants"

module Sensu
  module Server
    class Tessen
      attr_accessor :settings, :logger, :redis, :options
      attr_reader :timers

      # Create a new instance of Tessen. The instance variable
      # `@timers` is use to track EventMachine timers for
      # stopping/shutdown.
      #
      # @param options [Hash] containing the Sensu server Settings,
      #   Logger, and Redis connection.
      def initialize(options={})
        @timers = []
        @settings = options[:settings]
        @logger = options[:logger]
        @redis = options[:redis]
        @options = @settings.to_hash.fetch(:tessen, {})
      end

      # Determine if Tessen is enabled (opt-in).
      #
      # @return [TrueClass, FalseClass]
      def enabled?
        enabled = @options[:enabled] == true
        unless enabled
          note = "tessen collects anonymized data to help inform the sensu team about installations"
          note << " - you can opt-in via configuration: {\"tessen\": {\"enabled\": true}}"
          @logger.info("the tessen call-home mechanism is not enabled", :note => note)
        end
        enabled
      end

      # Run Tessen, scheduling data reports (every 6h).
      def run
        schedule_data_reports
      end

      # Stop Tessen, cancelling and clearing timers.
      def stop
        @timers.each do |timer|
          timer.cancel
        end
        @timers.clear
      end

      # Schedule data reports, sending data to the Tessen service
      # immediately and then every 6 hours after that.
      def schedule_data_reports
        send_data
        @timers << EM::PeriodicTimer.new(21600) do
          send_data
        end
      end

      # Send data to the Tessen service.
      def send_data(&block)
        create_data do |data|
          tessen_api_request(data, &block)
        end
      end

      # Create data to be sent to the Tessen service.
      #
      # @return [Hash]
      def create_data
        get_install_id do |install_id|
          get_client_count do |client_count|
            get_server_count do |server_count|
              identity_key = @options.fetch(:identity_key, "")
              flavour, version = get_version_info
              timestamp = Time.now.to_i
              data = {
                :tessen_identity_key => identity_key,
                :install => {
                  :id => install_id,
                  :sensu_flavour => flavour,
                  :sensu_version => version
                },
                :metrics => {
                  :points => [
                    {
                      :name => "client_count",
                      :value => client_count,
                      :timestamp => timestamp
                    },
                    {
                      :name => "server_count",
                      :value => server_count,
                      :timestamp => timestamp
                    }
                  ]
                }
              }
              yield data
            end
          end
        end
      end

      # Get the Sensu installation ID. The ID is randomly generated
      # and stored in Redis. This ID provides context and allows
      # multiple Sensu servers to report data for the same installation.
      def get_install_id
        @redis.setnx("tessen:install_id", rand(36**12).to_s(36)) do |created|
          @redis.get("tessen:install_id") do |install_id|
            yield install_id
          end
        end
      end

      # Get the Sensu client count for the installation. This count
      # currently includes proxy clients.
      #
      # @yield [count]
      # @yieldparam [Integer] client count
      def get_client_count
        @redis.scard("clients") do |count|
          yield count.to_i
        end
      end

      # Get the Sensu server count for the installation.
      #
      # @yield [count]
      # @yieldparam [Integer] server count
      def get_server_count
        @redis.scard("servers") do |count|
          yield count.to_i
        end
      end

      # Get the Sensu version info for the local Sensu service.
      def get_version_info
        if defined?(Sensu::Enterprise::VERSION)
          ["enterprise", Sensu::Enterprise::VERSION]
        else
          ["core", Sensu::VERSION]
        end
      end

      # Make a Tessen service API request.
      #
      # @param data [Hash]
      def tessen_api_request(data)
        @logger.debug("sending data to the tessen call-home service", {
          :data => data,
          :options => @options
        })
        connection = {}
        connection[:proxy] = @options[:proxy] if @options[:proxy]
        post_options = {:body => Sensu::JSON.dump(data)}
        http = EM::HttpRequest.new("https://tessen.sensu.io/v1/data", connection).post(post_options)
        http.callback do
          @logger.debug("tessen call-home service response", :status => http.response_header.status)
          yield if block_given?
        end
        http.errback do
          @logger.debug("tessen call-home service error", :error => http.error)
          yield if block_given?
        end
      end
    end
  end
end
