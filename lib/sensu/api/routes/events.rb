require "sensu/api/utilities/resolve_event"

module Sensu
  module API
    module Routes
      module Events
        include Utilities::ResolveEvent

        EVENTS_URI = /^\/(?:events|incidents)$/
        EVENTS_CLIENT_URI = /^\/(?:events|incidents)\/([\w\.-]+)$/
        EVENT_URI = /^\/(?:events|incidents)\/([\w\.-]+)\/([\w\.-]+)$/

        # GET /events
        def get_events
          @response_content = []
          raw_event_json = []
          @redis.smembers("clients") do |clients|
            unless clients.empty?
              clients.each_with_index do |client_name, index|
                @redis.hgetall("events:#{client_name}") do |events|
                  events.each do |check_name, event_json|
                    raw_event_json << event_json
                  end
                  if index == clients.length - 1
                    raw_event_json = pagination(raw_event_json)
                    raw_event_json.each do |event_json|
                      @response_content << Sensu::JSON.load(event_json)
                    end
                    respond
                  end
                end
              end
            else
              respond
            end
          end
        end

        # GET /events/:client_name
        def get_events_client
          client_name = parse_uri(EVENTS_CLIENT_URI).first
          @response_content = []
          raw_event_json = []
          @redis.hgetall("events:#{client_name}") do |events|
            events.each do |check_name, event_json|
              raw_event_json << event_json
            end
            raw_event_json = pagination(raw_event_json)
            raw_event_json.each do |event_json|
              @response_content << Sensu::JSON.load(event_json)
            end
            respond
          end
        end

        # GET /events/:client_name/:check_name
        def get_event
          client_name, check_name = parse_uri(EVENT_URI)
          @redis.hgetall("events:#{client_name}") do |events|
            event_json = events[check_name]
            unless event_json.nil?
              @response_content = Sensu::JSON.load(event_json)
              respond
            else
              not_found!
            end
          end
        end

        # DELETE /events/:client_name/:check_name
        def delete_event
          client_name, check_name = parse_uri(EVENT_URI)
          @redis.hgetall("events:#{client_name}") do |events|
            if events.include?(check_name)
              resolve_event(events[check_name])
              @response_content = {:issued => Time.now.to_i}
              accepted!
            else
              not_found!
            end
          end
        end
      end
    end
  end
end
