require "sensu/daemon"
require "sensu/server/filter"
require "sensu/server/mutate"
require "sensu/server/handle"

module Sensu
  module Server
    class Process
      include Daemon
      include Filter
      include Mutate
      include Handle

      attr_reader :is_master, :event_processing_count

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
        @event_processing_count = 0
      end

      def update_client_registry(client, &callback)
        @logger.debug("updating client registry", :client => client)
        @redis.set("client:#{client[:name]}", MultiJson.dump(client)) do
          @redis.sadd("clients", client[:name]) do
            callback.call
          end
        end
      end

      def setup_keepalives
        @logger.debug("subscribing to keepalives")
        @transport.subscribe(:direct, "keepalives", "keepalives", :ack => true) do |message_info, message|
          @logger.debug("received keepalive", :message => message)
          begin
            client = MultiJson.load(message)
            update_client_registry(client) do
              @transport.ack(message_info)
            end
          rescue MultiJson::ParseError => error
            @logger.error("failed to parse keepalive payload", {
              :message => message,
              :error => error.to_s
            })
            @transport.ack(message_info)
          end
        end
      end

      def expand_handler_sets(handler, depth=0)
        if handler[:type] == "set"
          if depth < 2
            derive_handlers(handler[:handlers], depth + 1)
          else
            @logger.error("handler sets cannot be deeply nested", :handler => handler)
            nil
          end
        else
          handler
        end
      end

      def derive_handlers(handler_list, depth=0)
        handler_list.compact.map { |handler_name|
          case
          when @settings.handler_exists?(handler_name)
            handler = @settings[:handlers][handler_name].merge(:name => handler_name)
            expand_handler_sets(handler, depth)
          when @extensions.handler_exists?(handler_name)
            @extensions[:handlers][handler_name]
          else
            @logger.error("unknown handler", :handler_name => handler_name)
            nil
          end
        }.flatten.compact.uniq
      end

      def event_bridges(event)
        @extensions[:bridges].each do |name, bridge|
          bridge.safe_run(event) do |output, status|
            @logger.debug("bridge extension output", {
              :extension => bridge.definition,
              :output => output
            })
          end
        end
      end

      def process_event(event, &callback)
        @event_processing_count += 1
        log_level = event[:check][:type] == "metric" ? :debug : :info
        @logger.send(log_level, "processing event", :event => event)
        event_bridges(event)
        handler_list = Array((event[:check][:handlers] || event[:check][:handler]) || "default")
        handlers = derive_handlers(handler_list)
        handlers.each do |handler|
          filter_event(handler, event) do |event|
            mutate_event(handler, event) do |event_data|
              handle_event(handler, event_data)
            end
          end
        end
      end

      def aggregate_check_result(result)
        @logger.debug("adding check result to aggregate", :result => result)
        check = result[:check]
        result_set = "#{check[:name]}:#{check[:issued]}"
        result_data = MultiJson.dump(:output => check[:output], :status => check[:status])
        @redis.hset("aggregation:#{result_set}", result[:client], result_data) do
          SEVERITIES.each do |severity|
            @redis.hsetnx("aggregate:#{result_set}", severity, 0)
          end
          severity = (SEVERITIES[check[:status]] || "unknown")
          @redis.hincrby("aggregate:#{result_set}", severity, 1) do
            @redis.hincrby("aggregate:#{result_set}", "total", 1) do
              @redis.sadd("aggregates:#{check[:name]}", check[:issued]) do
                @redis.sadd("aggregates", check[:name])
              end
            end
          end
        end
      end
    end
  end
end
