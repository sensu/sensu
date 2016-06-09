require "sensu/api/utilities/resolve_event"

module Sensu
  module API
    module Routes
      module Events
        include Utilities::ResolveEvent

        EVENTS_URI = /^\/events$/
        EVENTS_CLIENT_URI = /^\/events\/([\w\.-]+)$/
        EVENT_URI = /^\/events\/([\w\.-]+)\/([\w\.-]+)$/

        def get_events
          @response_content = []
          @redis.smembers("clients") do |clients|
            unless clients.empty?
              clients.each_with_index do |client_name, index|
                @redis.hgetall("events:#{client_name}") do |events|
                  events.each do |check_name, event_json|
                    @response_content << Sensu::JSON.load(event_json)
                  end
                  if index == clients.length - 1
                    respond
                  end
                end
              end
            else
              respond
            end
          end
        end

        def get_events_client
          client_name = EVENTS_CLIENT_URI.match(@http_request_uri)[1]
          @response_content = []
          @redis.hgetall("events:#{client_name}") do |events|
            events.each do |check_name, event_json|
              @response_content << Sensu::JSON.load(event_json)
            end
            respond
          end
        end

        def get_event
          uri_match = EVENT_URI.match(@http_request_uri)
          client_name = uri_match[1]
          check_name = uri_match[2]
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

        def delete_event
          uri_match = EVENT_URI.match(@http_request_uri)
          client_name = uri_match[1]
          check_name = uri_match[2]
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
