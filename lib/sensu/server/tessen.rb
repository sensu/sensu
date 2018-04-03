require "em-http-request"
require "sensu/constants"

module Sensu
  module Server
    class Tessen
      attr_accessor :logger, :redis

      def initialize
        @timers = []
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
            data = {
              :token => "",
              :install => {
                :id => install_id,
                :type => "core",
                :version => Sensu::VERSION
              },
              :metrics => {
                :points => [
                  {
                    :name => "client_count",
                    :value => client_count,
                    :timestamp => Time.now.to_i
                  }
                ]
              }
            }
            yield data
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

      def tessen_api_request(data)
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
