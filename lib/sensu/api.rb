require 'sensu/daemon'

gem 'thin', '1.5.0'
gem 'sinatra', '1.3.5'
gem 'async_sinatra', '1.0.0'

require 'thin'
require 'sinatra/async'

module Sensu
  class API < Sinatra::Base
    register Sinatra::Async

    class << self
      include Daemon

      def run(options={})
        bootstrap(options)
        EM::run do
          start
          setup_signal_traps
        end
      end

      def bootstrap(options)
        setup_logger(options)
        set :logger, @logger
        load_settings(options)
        if @settings[:api][:user] && @settings[:api][:password]
          use Rack::Auth::Basic do |user, password|
            user == @settings[:api][:user] && password == @settings[:api][:password]
          end
        end
        set :checks, @settings[:checks]
        set :all_checks, @settings.checks
        setup_process(options)
      end

      def start
        setup_redis
        set :redis, @redis
        setup_transport
        set :transport, @transport
        Thin::Logging.silent = true
        bind = @settings[:api][:bind] || '0.0.0.0'
        Thin::Server.start(bind, @settings[:api][:port], self)
      end

      def stop
        @logger.warn('stopping')
        @redis.close
        @transport.close
        super
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
      ''
    end

    error do
      ''
    end

    helpers do
      def request_log_line
        settings.logger.info([env['REQUEST_METHOD'], env['REQUEST_PATH']].join(' '), {
          :remote_address => env['REMOTE_ADDR'],
          :user_agent => env['HTTP_USER_AGENT'],
          :request_method => env['REQUEST_METHOD'],
          :request_uri => env['REQUEST_URI'],
          :request_body => env['rack.input'].read
        })
        env['rack.input'].rewind
      end

      def bad_request!
        ahalt 400
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
        body ''
      end

      def read_data(rules={}, &block)
        begin
          data = MultiJson.load(env['rack.input'].read)
          valid = rules.all? do |key, rule|
            data[key].is_a?(rule[:type]) || (rule[:nil_ok] && data[key].nil?)
          end
          if valid
            block.call(data)
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
          headers['X-Pagination'] = MultiJson.dump(
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

      def transport_info(&block)
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
          settings.transport.stats('keepalives') do |stats|
            info[:keepalives] = stats
            settings.transport.stats('results') do |stats|
              info[:results] = stats
              block.call(info)
            end
          end
        else
          block.call(info)
        end
      end

      def event_hash(event_json, client_name, check_name)
        MultiJson.load(event_json).merge(
          :client => client_name,
          :check => check_name
        )
      end

      def resolve_event(event)
        payload = {
          :client => event[:client],
          :check => {
            :name => event[:check],
            :output => 'Resolving on request of the API',
            :status => 0,
            :issued => Time.now.to_i,
            :handlers => event[:handlers],
            :force_resolve => true
          }
        }
        settings.logger.info('publishing check result', {
          :payload => payload
        })
        settings.transport.publish(:direct, 'results', MultiJson.dump(payload)) do |info|
          if info[:error]
            settings.logger.error('failed to publish check result', {
              :payload => payload,
              :error => info[:error].to_s
            })
          end
        end
      end
    end

    before do
      request_log_line
      content_type 'application/json'
    end

    aget '/info/?' do
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

    aget '/health/?' do
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

    aget '/clients/?' do
      response = Array.new
      settings.redis.smembers('clients') do |clients|
        clients = pagination(clients)
        unless clients.empty?
          clients.each_with_index do |client_name, index|
            settings.redis.get('client:' + client_name) do |client_json|
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
      settings.redis.get('client:' + client_name) do |client_json|
        unless client_json.nil?
          body client_json
        else
          not_found!
        end
      end
    end

    aget %r{/clients/([\w\.-]+)/history/?$} do |client_name|
      response = Array.new
      settings.redis.smembers('history:' + client_name) do |checks|
        unless checks.empty?
          checks.each_with_index do |check_name, index|
            history_key = 'history:' + client_name + ':' + check_name
            settings.redis.lrange(history_key, -21, -1) do |history|
              history.map! do |status|
                status.to_i
              end
              execution_key = 'execution:' + client_name + ':' + check_name
              settings.redis.get(execution_key) do |last_execution|
                unless history.empty? || last_execution.nil?
                  item = {
                    :check => check_name,
                    :history => history,
                    :last_execution => last_execution.to_i,
                    :last_status => history.last
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
      settings.redis.get('client:' + client_name) do |client_json|
        unless client_json.nil?
          settings.redis.hgetall('events:' + client_name) do |events|
            events.each do |check_name, event_json|
              resolve_event(event_hash(event_json, client_name, check_name))
            end
            EM::Timer.new(5) do
              client = MultiJson.load(client_json)
              settings.logger.info('deleting client', {
                :client => client
              })
              settings.redis.srem('clients', client_name) do
                settings.redis.del('client:' + client_name)
                settings.redis.del('events:' + client_name)
                settings.redis.smembers('history:' + client_name) do |checks|
                  checks.each do |check_name|
                    settings.redis.del('history:' + client_name + ':' + check_name)
                    settings.redis.del('execution:' + client_name + ':' + check_name)
                  end
                  settings.redis.del('history:' + client_name)
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

    aget '/checks/?' do
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

    apost '/request/?' do
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
          settings.logger.info('publishing check request', {
            :payload => payload,
            :subscribers => subscribers
          })
          subscribers.uniq.each do |exchange_name|
            settings.transport.publish(:fanout, exchange_name, MultiJson.dump(payload)) do |info|
              if info[:error]
                settings.logger.error('failed to publish check request', {
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

    aget '/events/?' do
      response = Array.new
      settings.redis.smembers('clients') do |clients|
        unless clients.empty?
          clients.each_with_index do |client_name, index|
            settings.redis.hgetall('events:' + client_name) do |events|
              events.each do |check_name, event_json|
                response << event_hash(event_json, client_name, check_name)
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
      settings.redis.hgetall('events:' + client_name) do |events|
        events.each do |check_name, event_json|
          response << event_hash(event_json, client_name, check_name)
        end
        body MultiJson.dump(response)
      end
    end

    aget %r{/events?/([\w\.-]+)/([\w\.-]+)/?$} do |client_name, check_name|
      settings.redis.hgetall('events:' + client_name) do |events|
        event_json = events[check_name]
        unless event_json.nil?
          body MultiJson.dump(event_hash(event_json, client_name, check_name))
        else
          not_found!
        end
      end
    end

    adelete %r{/events?/([\w\.-]+)/([\w\.-]+)/?$} do |client_name, check_name|
      settings.redis.hgetall('events:' + client_name) do |events|
        if events.include?(check_name)
          resolve_event(event_hash(events[check_name], client_name, check_name))
          issued!
        else
          not_found!
        end
      end
    end

    apost '/resolve/?' do
      rules = {
        :client => {:type => String, :nil_ok => false},
        :check => {:type => String, :nil_ok => false}
      }
      read_data(rules) do |data|
        settings.redis.hgetall('events:' + data[:client]) do |events|
          if events.include?(data[:check])
            resolve_event(event_hash(events[data[:check]], data[:client], data[:check]))
            issued!
          else
            not_found!
          end
        end
      end
    end

    aget '/aggregates/?' do
      response = Array.new
      settings.redis.smembers('aggregates') do |checks|
        unless checks.empty?
          checks.each_with_index do |check_name, index|
            settings.redis.smembers('aggregates:' + check_name) do |aggregates|
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
      settings.redis.smembers('aggregates:' + check_name) do |aggregates|
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
      settings.redis.smembers('aggregates:' + check_name) do |aggregates|
        unless aggregates.empty?
          aggregates.each do |check_issued|
            result_set = check_name + ':' + check_issued
            settings.redis.del('aggregation:' + result_set)
            settings.redis.del('aggregate:' + result_set)
          end
          settings.redis.del('aggregates:' + check_name) do
            settings.redis.srem('aggregates', check_name) do
              no_content!
            end
          end
        else
          not_found!
        end
      end
    end

    aget %r{/aggregates?/([\w\.-]+)/([\w\.-]+)/?$} do |check_name, check_issued|
      result_set = check_name + ':' + check_issued
      settings.redis.hgetall('aggregate:' + result_set) do |aggregate|
        unless aggregate.empty?
          response = aggregate.inject(Hash.new) do |totals, (status, count)|
            totals[status] = Integer(count)
            totals
          end
          settings.redis.hgetall('aggregation:' + result_set) do |results|
            parsed_results = results.inject(Array.new) do |parsed, (client_name, check_json)|
              check = MultiJson.load(check_json)
              parsed << check.merge(:client => client_name)
            end
            if params[:summarize]
              options = params[:summarize].split(',')
              if options.include?('output')
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
        settings.redis.set('stash:' + path, MultiJson.dump(data)) do
          settings.redis.sadd('stashes', path) do
            created!(MultiJson.dump(:path => path))
          end
        end
      end
    end

    aget %r{/stash(?:es)?/(.*)/?} do |path|
      settings.redis.get('stash:' + path) do |stash_json|
        unless stash_json.nil?
          body stash_json
        else
          not_found!
        end
      end
    end

    adelete %r{/stash(?:es)?/(.*)/?} do |path|
      settings.redis.exists('stash:' + path) do |stash_exists|
        if stash_exists
          settings.redis.srem('stashes', path) do
            settings.redis.del('stash:' + path) do
              no_content!
            end
          end
        else
          not_found!
        end
      end
    end

    aget '/stashes/?' do
      response = Array.new
      settings.redis.smembers('stashes') do |stashes|
        unless stashes.empty?
          stashes.each_with_index do |path, index|
            settings.redis.get('stash:' + path) do |stash_json|
              settings.redis.ttl('stash:' + path) do |ttl|
                unless stash_json.nil?
                  item = {
                    :path => path,
                    :content => MultiJson.load(stash_json),
                    :expire => ttl
                  }
                  response << item
                else
                  settings.redis.srem('stashes', path)
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

    apost '/stashes/?' do
      rules = {
        :path => {:type => String, :nil_ok => false},
        :content => {:type => Hash, :nil_ok => false},
        :expire => {:type => Integer, :nil_ok => true}
      }
      read_data(rules) do |data|
        stash_key = 'stash:' + data[:path]
        settings.redis.set(stash_key, MultiJson.dump(data[:content])) do
          settings.redis.sadd('stashes', data[:path]) do
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
