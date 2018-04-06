require "em-http-request"
require "sensu/constants"

module Sensu
  module Server
    class Tessen
      attr_accessor :settings, :logger, :redis

      def initialize
        @timers = []
      end

      def enabled?
        tessen = @settings.to_hash.fetch(:tessen, {})
        tessen[:enabled] != false
      end

      def run
        schedule_reports
      end

      def stop
        @timers.each do |timer|
          timer.cancel
        end
        @timers.clear
      end

      private

      def schedule_reports
        send_data
        @timers << EM::PeriodicTimer.new(21600) do
          send_data
        end
      end

      def send_data
        create_data do |data|
          tessen_api_request(data)
        end
      end

      def create_data
        get_install_id do |install_id|
          get_client_count do |client_count|
            get_server_count do |server_count|
              type, version = get_version_info
              timestamp = Time.now.to_i
              data = {
                :token => "",
                :install => {
                  :id => install_id,
                  :type => type,
                  :version => version
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

      def get_install_id
        @redis.setnx("tessen:install_id", rand(36**12).to_s(36)) do |created|
          @redis.get("tessen:install_id") do |install_id|
            yield install_id
          end
        end
      end

      def get_client_count
        @redis.scard("clients") do |count|
          yield count.to_i
        end
      end

      def get_server_count
        @redis.scard("servers") do |count|
          yield count.to_i
        end
      end

      def get_version_info
        if defined?(Sensu::Enterprise::VERSION)
          ["enterprise", Sensu::Enterprise::VERSION]
        else
          ["core", Sensu::VERSION]
        end
      end

      def tessen_api_request(data)
        note = "this anonymized data helps inform the sensu team about installations"
        note << " - you can choose to opt-out via configuration: {\"tessen\": {\"enabled\": false}}"
        @logger.debug("sending data to the tessen call-home service", {
          :data => data,
          :note => note
        })
        options = {:body => Sensu::JSON.dump(data)}
        http = EM::HttpRequest.new("https://tessen.sensu.io/v1/data").post(options)
        http.callback do
          @logger.debug("tessen response", :status => http.response_header.status)
        end
        http.errback do
          @logger.debug("tessen error", :error => http.error)
        end
      end
    end
  end
end
