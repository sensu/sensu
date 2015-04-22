require "sensu/daemon"

gem "sinatra", "1.3.5"
gem "async_sinatra", "1.0.0"

unless RUBY_PLATFORM =~ /java/
  gem "thin", "1.5.0"
  require "thin"
end

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
            start
            setup_signal_traps
          end
        end

        def on_reactor_run
          EM::next_tick do
            setup_redis
            set :redis, @redis
            setup_transport
            set :transport, @transport
          end
        end

        def bootstrap(options)
          setup_logger(options)
          set :logger, @logger
          load_settings(options)
          set :api, @settings[:api] || {}
          set :checks, @settings[:checks]
          set :all_checks, @settings.checks
          set :cors, @settings[:cors] || {
            "Origin" => "*",
            "Methods" => "GET, POST, PUT, DELETE, OPTIONS",
            "Credentials" => "true",
            "Headers" => "Origin, X-Requested-With, Content-Type, Accept, Authorization"
          }
          on_reactor_run
          self
        end

        def start_server
          Thin::Logging.silent = true
          bind = settings.api[:bind] || "0.0.0.0"
          port = settings.api[:port] || 4567
          @logger.info("api listening", {
            :bind => bind,
            :port => port
          })
          @thin = Thin::Server.new(bind, port, self)
          @thin.start
        end

        def stop_server(&callback)
          @thin.stop
          retry_until_true do
            unless @thin.running?
              callback.call
              true
            end
          end
        end

        def start
          start_server
          super
        end

        def stop
          @logger.warn("stopping")
          stop_server do
            @redis.close
            @transport.close
            super
          end
        end

        def test(options={})
          bootstrap(options)
          start
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
        def request_log_line
          settings.logger.info([env["REQUEST_METHOD"], env["REQUEST_PATH"]].join(" "), {
            :remote_address => env["REMOTE_ADDR"],
            :user_agent => env["HTTP_USER_AGENT"],
            :request_method => env["REQUEST_METHOD"],
            :request_uri => env["REQUEST_URI"],
            :request_body => env["rack.input"].read
          })
          env["rack.input"].rewind
        end

        def protected!
          if settings.api[:user] && settings.api[:password]
            return if !(settings.api[:user] && settings.api[:password]) || authorized?
            headers["WWW-Authenticate"] = 'Basic realm="Restricted Area"'
            unauthorized!
          end
        end

        def authorized?
          @auth ||=  Rack::Auth::Basic::Request.new(request.env)
          @auth.provided? &&
            @auth.basic? &&
            @auth.credentials &&
            @auth.credentials == [settings.api[:user], settings.api[:password]]
        end

        def bad_request!
          ahalt 400
        end

        def unauthorized!
          throw(:halt, [401, ""])
        end

        def not_found!
          ahalt 404
        end

        def unavailable!
          ahalt 503
        end

        def created!(response)
          status 201
          body response
        end

        def accepted!(response)
          status 202
          body response
        end

        def issued!
          accepted!(MultiJson.dump(:issued => Time.now.to_i))
        end

        def no_content!
          status 204
          body ""
        end

        def read_data(rules={}, &callback)
          begin
            data = MultiJson.load(env["rack.input"].read)
            valid = rules.all? do |key, rule|
              value = data[key]
              (value.is_a?(rule[:type]) || (rule[:nil_ok] && value.nil?)) &&
                rule[:regex].nil? || (rule[:regex] && (value =~ rule[:regex]) == 0)
            end
            if valid
              callback.call(data)
            else
              bad_request!
            end
          rescue MultiJson::ParseError
            bad_request!
          end
        end

        def integer_parameter(parameter)
          parameter =~ /^[0-9]+$/ ? parameter.to_i : nil
        end

        def pagination(items)
          limit = integer_parameter(params[:limit])
          offset = integer_parameter(params[:offset]) || 0
          unless limit.nil?
            headers["X-Pagination"] = MultiJson.dump(
              :limit => limit,
              :offset => offset,
              :total => items.size
            )
            paginated = items.slice(offset, limit)
            Array(paginated)
          else
            items
          end
        end

        def transport_info(&callback)
          info = {
            :keepalives => {
              :messages => nil,
              :consumers => nil
            },
            :results => {
              :messages => nil,
              :consumers => nil
            },
            :connected => settings.transport.connected?
          }
          if settings.transport.connected?
            settings.transport.stats("keepalives") do |stats|
              info[:keepalives] = stats
              settings.transport.stats("results") do |stats|
                info[:results] = stats
                callback.call(info)
              end
            end
          else
            callback.call(info)
          end
        end

        def resolve_event(event_json)
          event = MultiJson.load(event_json)
          check = event[:check].merge(
            :output => "Resolving on request of the API",
            :status => 0,
            :issued => Time.now.to_i,
            :executed => Time.now.to_i,
            :force_resolve => true
          )
          check.delete(:history)
          payload = {
            :client => event[:client][:name],
            :check => check
          }
          settings.logger.info("publishing check result", :payload => payload)
          settings.transport.publish(:direct, "results", MultiJson.dump(payload)) do |info|
            if info[:error]
              settings.logger.error("failed to publish check result", {
                :payload => payload,
                :error => info[:error].to_s
              })
            end
          end
        end
      end

      before do
        request_log_line
        content_type "application/json"
        settings.cors.each do |header, value|
          headers["Access-Control-Allow-#{header}"] = value
        end
        protected! unless env["REQUEST_METHOD"] == "OPTIONS"
      end

      aoptions "/*" do
        body ""
      end

      aget "/info/?" do
        transport_info do |info|
          response = {
            :sensu => {
              :version => VERSION
            },
            :transport => info,
            :redis => {
              :connected => settings.redis.connected?
            }
          }
          body MultiJson.dump(response)
        end
      end

      aget "/health/?" do
        if settings.redis.connected? && settings.transport.connected?
          healthy = Array.new
          min_consumers = integer_parameter(params[:consumers])
          max_messages = integer_parameter(params[:messages])
          transport_info do |info|
            if min_consumers
              healthy << (info[:keepalives][:consumers] >= min_consumers)
              healthy << (info[:results][:consumers] >= min_consumers)
            end
            if max_messages
              healthy << (info[:keepalives][:messages] <= max_messages)
              healthy << (info[:results][:messages] <= max_messages)
            end
            healthy.all? ? no_content! : unavailable!
          end
        else
          unavailable!
        end
      end

      apost "/clients/?" do
        rules = {
          :name => {:type => String, :nil_ok => false, :regex => /^[\w\.-]+$/},
          :address => {:type => String, :nil_ok => false},
          :subscriptions => {:type => Array, :nil_ok => false}
        }
        read_data(rules) do |data|
          data[:keepalives] = false
          data[:timestamp] = Time.now.to_i
          settings.redis.set("client:#{data[:name]}", MultiJson.dump(data)) do
            settings.redis.sadd("clients", data[:name]) do
              created!(MultiJson.dump(:name => data[:name]))
            end
          end
        end
      end

      aget "/clients/?" do
        response = Array.new
        settings.redis.smembers("clients") do |clients|
          clients = pagination(clients)
          unless clients.empty?
            clients.each_with_index do |client_name, index|
              settings.redis.get("client:#{client_name}") do |client_json|
                response << MultiJson.load(client_json)
                if index == clients.size - 1
                  body MultiJson.dump(response)
                end
              end
            end
          else
            body MultiJson.dump(response)
          end
        end
      end

      aget %r{/clients?/([\w\.-]+)/?$} do |client_name|
        settings.redis.get("client:#{client_name}") do |client_json|
          unless client_json.nil?
            body client_json
          else
            not_found!
          end
        end
      end

      aget %r{/clients/([\w\.-]+)/history/?$} do |client_name|
        response = Array.new
        settings.redis.smembers("result:#{client_name}") do |checks|
          unless checks.empty?
            checks.each_with_index do |check_name, index|
              result_key = "#{client_name}:#{check_name}"
              history_key = "history:#{result_key}"
              settings.redis.lrange(history_key, -21, -1) do |history|
                history.map! do |status|
                  status.to_i
                end
                settings.redis.get("result:#{result_key}") do |result_json|
                  result = MultiJson.load(result_json)
                  last_execution = result[:executed]
                  unless history.empty? || last_execution.nil?
                    item = {
                      :check => check_name,
                      :history => history,
                      :last_execution => last_execution.to_i,
                      :last_status => history.last,
                      :last_result => result
                    }
                    response << item
                  end
                  if index == checks.size - 1
                    body MultiJson.dump(response)
                  end
                end
              end
            end
          else
            body MultiJson.dump(response)
          end
        end
      end

      adelete %r{/clients?/([\w\.-]+)/?$} do |client_name|
        settings.redis.get("client:#{client_name}") do |client_json|
          unless client_json.nil?
            settings.redis.hgetall("events:#{client_name}") do |events|
              events.each do |check_name, event_json|
                resolve_event(event_json)
              end
              EM::Timer.new(5) do
                client = MultiJson.load(client_json)
                settings.logger.info("deleting client", :client => client)
                settings.redis.srem("clients", client_name) do
                  settings.redis.del("client:#{client_name}")
                  settings.redis.del("events:#{client_name}")
                  settings.redis.smembers("result:#{client_name}") do |checks|
                    checks.each do |check_name|
                      result_key = "#{client_name}:#{check_name}"
                      settings.redis.del("result:#{result_key}")
                      settings.redis.del("history:#{result_key}")
                    end
                    settings.redis.del("result:#{client_name}")
                  end
                end
              end
              issued!
            end
          else
            not_found!
          end
        end
      end

      aget "/checks/?" do
        body MultiJson.dump(settings.all_checks)
      end

      aget %r{/checks?/([\w\.-]+)/?$} do |check_name|
        if settings.checks[check_name]
          response = settings.checks[check_name].merge(:name => check_name)
          body MultiJson.dump(response)
        else
          not_found!
        end
      end

      apost "/request/?" do
        rules = {
          :check => {:type => String, :nil_ok => false},
          :subscribers => {:type => Array, :nil_ok => true}
        }
        read_data(rules) do |data|
          if settings.checks[data[:check]]
            check = settings.checks[data[:check]]
            subscribers = data[:subscribers] || check[:subscribers] || Array.new
            payload = {
              :name => data[:check],
              :command => check[:command],
              :issued => Time.now.to_i
            }
            settings.logger.info("publishing check request", {
              :payload => payload,
              :subscribers => subscribers
            })
            subscribers.uniq.each do |exchange_name|
              settings.transport.publish(:fanout, exchange_name.to_s, MultiJson.dump(payload)) do |info|
                if info[:error]
                  settings.logger.error("failed to publish check request", {
                    :exchange_name => exchange_name,
                    :payload => payload,
                    :error => info[:error].to_s
                  })
                end
              end
            end
            issued!
          else
            not_found!
          end
        end
      end

      aget "/events/?" do
        response = Array.new
        settings.redis.smembers("clients") do |clients|
          unless clients.empty?
            clients.each_with_index do |client_name, index|
              settings.redis.hgetall("events:#{client_name}") do |events|
                events.each do |check_name, event_json|
                  response << MultiJson.load(event_json)
                end
                if index == clients.size - 1
                  body MultiJson.dump(response)
                end
              end
            end
          else
            body MultiJson.dump(response)
          end
        end
      end

      aget %r{/events/([\w\.-]+)/?$} do |client_name|
        response = Array.new
        settings.redis.hgetall("events:#{client_name}") do |events|
          events.each do |check_name, event_json|
            response << MultiJson.load(event_json)
          end
          body MultiJson.dump(response)
        end
      end

      aget %r{/events?/([\w\.-]+)/([\w\.-]+)/?$} do |client_name, check_name|
        settings.redis.hgetall("events:#{client_name}") do |events|
          event_json = events[check_name]
          unless event_json.nil?
            body event_json
          else
            not_found!
          end
        end
      end

      adelete %r{/events?/([\w\.-]+)/([\w\.-]+)/?$} do |client_name, check_name|
        settings.redis.hgetall("events:#{client_name}") do |events|
          if events.include?(check_name)
            resolve_event(events[check_name])
            issued!
          else
            not_found!
          end
        end
      end

      apost "/resolve/?" do
        rules = {
          :client => {:type => String, :nil_ok => false},
          :check => {:type => String, :nil_ok => false}
        }
        read_data(rules) do |data|
          settings.redis.hgetall("events:#{data[:client]}") do |events|
            if events.include?(data[:check])
              resolve_event(events[data[:check]])
              issued!
            else
              not_found!
            end
          end
        end
      end

      aget "/aggregates/?" do
        response = Array.new
        settings.redis.smembers("aggregates") do |checks|
          unless checks.empty?
            checks.each_with_index do |check_name, index|
              settings.redis.smembers("aggregates:#{check_name}") do |aggregates|
                aggregates.reverse!
                aggregates.map! do |issued|
                  issued.to_i
                end
                item = {
                  :check => check_name,
                  :issued => aggregates
                }
                response << item
                if index == checks.size - 1
                  body MultiJson.dump(response)
                end
              end
            end
          else
            body MultiJson.dump(response)
          end
        end
      end

      aget %r{/aggregates/([\w\.-]+)/?$} do |check_name|
        settings.redis.smembers("aggregates:#{check_name}") do |aggregates|
          unless aggregates.empty?
            aggregates.reverse!
            aggregates.map! do |issued|
              issued.to_i
            end
            age = integer_parameter(params[:age])
            if age
              timestamp = Time.now.to_i - age
              aggregates.reject! do |issued|
                issued > timestamp
              end
            end
            body MultiJson.dump(pagination(aggregates))
          else
            not_found!
          end
        end
      end

      adelete %r{/aggregates/([\w\.-]+)/?$} do |check_name|
        settings.redis.smembers("aggregates:#{check_name}") do |aggregates|
          unless aggregates.empty?
            aggregates.each do |check_issued|
              result_set = "#{check_name}:#{check_issued}"
              settings.redis.del("aggregation:#{result_set}")
              settings.redis.del("aggregate:#{result_set}")
            end
            settings.redis.del("aggregates:#{check_name}") do
              settings.redis.srem("aggregates", check_name) do
                no_content!
              end
            end
          else
            not_found!
          end
        end
      end

      aget %r{/aggregates?/([\w\.-]+)/([\w\.-]+)/?$} do |check_name, check_issued|
        result_set = "#{check_name}:#{check_issued}"
        settings.redis.hgetall("aggregate:#{result_set}") do |aggregate|
          unless aggregate.empty?
            response = aggregate.inject(Hash.new) do |totals, (status, count)|
              totals[status] = Integer(count)
              totals
            end
            settings.redis.hgetall("aggregation:#{result_set}") do |results|
              parsed_results = results.inject(Array.new) do |parsed, (client_name, check_json)|
                check = MultiJson.load(check_json)
                parsed << check.merge(:client => client_name)
              end
              if params[:summarize]
                options = params[:summarize].split(",")
                if options.include?("output")
                  outputs = Hash.new(0)
                  parsed_results.each do |result|
                    outputs[result[:output]] += 1
                  end
                  response[:outputs] = outputs
                end
              end
              if params[:results]
                response[:results] = parsed_results
              end
              body MultiJson.dump(response)
            end
          else
            not_found!
          end
        end
      end

      apost %r{/stash(?:es)?/(.*)/?} do |path|
        read_data do |data|
          settings.redis.set("stash:#{path}", MultiJson.dump(data)) do
            settings.redis.sadd("stashes", path) do
              created!(MultiJson.dump(:path => path))
            end
          end
        end
      end

      aget %r{/stash(?:es)?/(.*)/?} do |path|
        settings.redis.get("stash:#{path}") do |stash_json|
          unless stash_json.nil?
            body stash_json
          else
            not_found!
          end
        end
      end

      adelete %r{/stash(?:es)?/(.*)/?} do |path|
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
                      :content => MultiJson.load(stash_json),
                      :expire => ttl
                    }
                    response << item
                  else
                    settings.redis.srem("stashes", path)
                  end
                  if index == stashes.size - 1
                    body MultiJson.dump(pagination(response))
                  end
                end
              end
            end
          else
            body MultiJson.dump(response)
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
          settings.redis.set(stash_key, MultiJson.dump(data[:content])) do
            settings.redis.sadd("stashes", data[:path]) do
              response = MultiJson.dump(:path => data[:path])
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
    end
  end
end
