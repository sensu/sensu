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

      aget "/aggregates/?" do
        settings.redis.smembers("aggregates") do |aggregates|
          aggregates.map! do |aggregate|
            {:name => aggregate}
          end
          body Sensu::JSON.dump(aggregates)
        end
      end

      aget %r{^/aggregates/([\w\.-]+)/?$} do |aggregate|
        response = {
          :clients => 0,
          :checks => 0,
          :results => {
            :ok => 0,
            :warning => 0,
            :critical => 0,
            :unknown => 0,
            :total => 0,
            :stale => 0
          }
        }
        settings.redis.smembers("aggregates:#{aggregate}") do |aggregate_members|
          unless aggregate_members.empty?
            clients = []
            checks = []
            results = []
            aggregate_members.each_with_index do |member, index|
              client_name, check_name = member.split(":")
              clients << client_name
              checks << check_name
              result_key = "result:#{client_name}:#{check_name}"
              settings.redis.get(result_key) do |result_json|
                unless result_json.nil?
                  results << Sensu::JSON.load(result_json)
                else
                  settings.redis.srem("aggregates:#{aggregate}", member)
                end
                if index == aggregate_members.length - 1
                  response[:clients] = clients.uniq.length
                  response[:checks] = checks.uniq.length
                  max_age = integer_parameter(params[:max_age])
                  if max_age
                    result_count = results.length
                    timestamp = Time.now.to_i - max_age
                    results.reject! do |result|
                      result[:executed] < timestamp
                    end
                    response[:results][:stale] = result_count - results.length
                  end
                  response[:results][:total] = results.length
                  results.each do |result|
                    severity = (SEVERITIES[result[:status]] || "unknown")
                    response[:results][severity.to_sym] += 1
                  end
                  body Sensu::JSON.dump(response)
                end
              end
            end
          else
            not_found!
          end
        end
      end

      adelete %r{^/aggregates/([\w\.-]+)/?$} do |aggregate|
        settings.redis.smembers("aggregates") do |aggregates|
          if aggregates.include?(aggregate)
            settings.redis.srem("aggregates", aggregate) do
              settings.redis.del("aggregates:#{aggregate}") do
                no_content!
              end
            end
          else
            not_found!
          end
        end
      end

      aget %r{^/aggregates/([\w\.-]+)/clients/?$} do |aggregate|
        response = Array.new
        settings.redis.smembers("aggregates:#{aggregate}") do |aggregate_members|
          unless aggregate_members.empty?
            clients = Hash.new
            aggregate_members.each do |member|
              client_name, check_name = member.split(":")
              clients[client_name] ||= []
              clients[client_name] << check_name
            end
            clients.each do |client_name, checks|
              response << {
                :name => client_name,
                :checks => checks
              }
            end
            body Sensu::JSON.dump(response)
          else
            not_found!
          end
        end
      end

      aget %r{^/aggregates/([\w\.-]+)/checks/?$} do |aggregate|
        response = Array.new
        settings.redis.smembers("aggregates:#{aggregate}") do |aggregate_members|
          unless aggregate_members.empty?
            checks = Hash.new
            aggregate_members.each do |member|
              client_name, check_name = member.split(":")
              checks[check_name] ||= []
              checks[check_name] << client_name
            end
            checks.each do |check_name, clients|
              response << {
                :name => check_name,
                :clients => clients
              }
            end
            body Sensu::JSON.dump(response)
          else
            not_found!
          end
        end
      end

      aget %r{^/aggregates/([\w\.-]+)/results/([\w\.-]+)/?$} do |aggregate, severity|
        response = Array.new
        if SEVERITIES.include?(severity)
          settings.redis.smembers("aggregates:#{aggregate}") do |aggregate_members|
            unless aggregate_members.empty?
              summaries = Hash.new
              max_age = integer_parameter(params[:max_age])
              current_timestamp = Time.now.to_i
              aggregate_members.each_with_index do |member, index|
                client_name, check_name = member.split(":")
                result_key = "result:#{client_name}:#{check_name}"
                settings.redis.get(result_key) do |result_json|
                  unless result_json.nil?
                    result = Sensu::JSON.load(result_json)
                    if SEVERITIES[result[:status]] == severity &&
                        (max_age.nil? || result[:executed] >= (current_timestamp - max_age))
                      summaries[check_name] ||= {}
                      summaries[check_name][result[:output]] ||= {:total => 0, :clients => []}
                      summaries[check_name][result[:output]][:total] += 1
                      summaries[check_name][result[:output]][:clients] << client_name
                    end
                  end
                  if index == aggregate_members.length - 1
                    summaries.each do |check_name, outputs|
                      summary = outputs.map do |output, output_summary|
                        {:output => output}.merge(output_summary)
                      end
                      response << {
                        :check => check_name,
                        :summary => summary
                      }
                    end
                    body Sensu::JSON.dump(response)
                  end
                end
              end
            else
              not_found!
            end
          end
        else
          bad_request!
        end
      end

      apost %r{^/stash(?:es)?/(.*)/?} do |path|
        read_data do |data|
          settings.redis.set("stash:#{path}", Sensu::JSON.dump(data)) do
            settings.redis.sadd("stashes", path) do
              created!(Sensu::JSON.dump(:path => path))
            end
          end
        end
      end

      aget %r{^/stash(?:es)?/(.*)/?} do |path|
        settings.redis.get("stash:#{path}") do |stash_json|
          unless stash_json.nil?
            body stash_json
          else
            not_found!
          end
        end
      end

      adelete %r{^/stash(?:es)?/(.*)/?} do |path|
        settings.redis.exists("stash:#{path}") do |stash_exists|
          if stash_exists
            settings.redis.srem("stashes", path) do
              settings.redis.del("stash:#{path}") do
                no_content!
              end
            end
          else
            not_found!
          end
        end
      end

      aget "/stashes/?" do
        response = Array.new
        settings.redis.smembers("stashes") do |stashes|
          unless stashes.empty?
            stashes.each_with_index do |path, index|
              settings.redis.get("stash:#{path}") do |stash_json|
                settings.redis.ttl("stash:#{path}") do |ttl|
                  unless stash_json.nil?
                    item = {
                      :path => path,
                      :content => Sensu::JSON.load(stash_json),
                      :expire => ttl
                    }
                    response << item
                  else
                    settings.redis.srem("stashes", path)
                  end
                  if index == stashes.length - 1
                    body Sensu::JSON.dump(pagination(response))
                  end
                end
              end
            end
          else
            body Sensu::JSON.dump(response)
          end
        end
      end

      apost "/stashes/?" do
        rules = {
          :path => {:type => String, :nil_ok => false},
          :content => {:type => Hash, :nil_ok => false},
          :expire => {:type => Integer, :nil_ok => true}
        }
        read_data(rules) do |data|
          stash_key = "stash:#{data[:path]}"
          settings.redis.set(stash_key, Sensu::JSON.dump(data[:content])) do
            settings.redis.sadd("stashes", data[:path]) do
              response = Sensu::JSON.dump(:path => data[:path])
              if data[:expire]
                settings.redis.expire(stash_key, data[:expire]) do
                  created!(response)
                end
              else
                created!(response)
              end
            end
          end
        end
      end

      apost "/results/?" do
        rules = {
          :name => {:type => String, :nil_ok => false, :regex => /\A[\w\.-]+\z/},
          :output => {:type => String, :nil_ok => false},
          :status => {:type => Integer, :nil_ok => true},
          :source => {:type => String, :nil_ok => true, :regex => /\A[\w\.-]+\z/}
        }
        read_data(rules) do |data|
          publish_check_result("sensu-api", data)
          issued!
        end
      end

      aget "/results/?" do
        response = Array.new
        settings.redis.smembers("clients") do |clients|
          unless clients.empty?
            clients.each_with_index do |client_name, client_index|
              settings.redis.smembers("result:#{client_name}") do |checks|
                if !checks.empty?
                  checks.each_with_index do |check_name, check_index|
                    result_key = "result:#{client_name}:#{check_name}"
                    settings.redis.get(result_key) do |result_json|
                      unless result_json.nil?
                        check = Sensu::JSON.load(result_json)
                        response << {:client => client_name, :check => check}
                      end
                      if client_index == clients.length - 1 && check_index == checks.length - 1
                        body Sensu::JSON.dump(response)
                      end
                    end
                  end
                elsif client_index == clients.length - 1
                  body Sensu::JSON.dump(response)
                end
              end
            end
          else
            body Sensu::JSON.dump(response)
          end
        end
      end

      aget %r{^/results?/([\w\.-]+)/?$} do |client_name|
        response = Array.new
        settings.redis.smembers("result:#{client_name}") do |checks|
          unless checks.empty?
            checks.each_with_index do |check_name, check_index|
              result_key = "result:#{client_name}:#{check_name}"
              settings.redis.get(result_key) do |result_json|
                unless result_json.nil?
                  check = Sensu::JSON.load(result_json)
                  response << {:client => client_name, :check => check}
                end
                if check_index == checks.length - 1
                  body Sensu::JSON.dump(response)
                end
              end
            end
          else
            not_found!
          end
        end
      end

      aget %r{^/results?/([\w\.-]+)/([\w\.-]+)/?$} do |client_name, check_name|
        result_key = "result:#{client_name}:#{check_name}"
        settings.redis.get(result_key) do |result_json|
          unless result_json.nil?
            check = Sensu::JSON.load(result_json)
            response = {:client => client_name, :check => check}
            body Sensu::JSON.dump(response)
          else
            not_found!
          end
        end
      end

      adelete %r{^/results?/([\w\.-]+)/([\w\.-]+)/?$} do |client_name, check_name|
        result_key = "result:#{client_name}:#{check_name}"
        settings.redis.exists(result_key) do |result_exists|
          if result_exists
            settings.redis.srem("result:#{client_name}", check_name) do
              settings.redis.del(result_key) do |result_json|
                no_content!
              end
            end
          else
            not_found!
          end
        end
      end
    end
  end
end
