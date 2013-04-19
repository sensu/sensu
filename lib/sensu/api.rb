require File.join(File.dirname(__FILE__), 'base')
require File.join(File.dirname(__FILE__), 'redis')

gem 'thin', '1.5.0'
gem 'sinatra', '1.3.5'
gem 'async_sinatra', '1.0.0'

require 'thin'
require 'sinatra/async'

module Sensu
  class API < Sinatra::Base
    register Sinatra::Async

    class << self
      def run(options={})
        EM::run do
          bootstrap(options)
          start
          trap_signals
        end
      end

      def bootstrap(options={})
        base = Base.new(options)
        $logger = base.logger
        $settings = base.settings
        base.setup_process
        if $settings[:api][:user] && $settings[:api][:password]
          use Rack::Auth::Basic do |user, password|
            user == $settings[:api][:user] && password == $settings[:api][:password]
          end
        end
      end

      def setup_redis
        $logger.debug('connecting to redis', {
          :settings => $settings[:redis]
        })
        $redis = Redis.connect($settings[:redis])
        $redis.on_error do |error|
          $logger.fatal('redis connection error', {
            :error => error.to_s
          })
          stop
        end
        $redis.before_reconnect do
          $logger.warn('reconnecting to redis')
        end
        $redis.after_reconnect do
          $logger.info('reconnected to redis')
        end
      end

      def setup_rabbitmq
        $logger.debug('connecting to rabbitmq', {
          :settings => $settings[:rabbitmq]
        })
        $rabbitmq = RabbitMQ.connect($settings[:rabbitmq])
        $rabbitmq.on_error do |error|
          $logger.fatal('rabbitmq connection error', {
            :error => error.to_s
          })
          stop
        end
        $rabbitmq.before_reconnect do
          $logger.warn('reconnecting to rabbitmq')
        end
        $rabbitmq.after_reconnect do
          $logger.info('reconnected to rabbitmq')
        end
        $amq = $rabbitmq.channel
      end

      def start
        setup_redis
        setup_rabbitmq
        Thin::Logging.silent = true
        bind = $settings[:api][:bind] || '0.0.0.0'
        Thin::Server.start(bind, $settings[:api][:port], self)
      end

      def stop
        $logger.warn('stopping')
        $rabbitmq.close
        $redis.close
        $logger.warn('stopping reactor')
        EM::stop_event_loop
      end

      def trap_signals
        $signals = Array.new
        STOP_SIGNALS.each do |signal|
          Signal.trap(signal) do
            $signals << signal
          end
        end
        EM::PeriodicTimer.new(1) do
          signal = $signals.shift
          if STOP_SIGNALS.include?(signal)
            $logger.warn('received signal', {
              :signal => signal
            })
            stop
          end
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
      ''
    end

    error do
      ''
    end

    helpers do
      def request_log_line
        $logger.info([env['REQUEST_METHOD'], env['REQUEST_PATH']].join(' '), {
          :remote_address => env['REMOTE_ADDR'],
          :user_agent => env['HTTP_USER_AGENT'],
          :request_method => env['REQUEST_METHOD'],
          :request_uri => env['REQUEST_URI'],
          :request_body => env['rack.input'].read
        })
        env['rack.input'].rewind
      end

      def integer_parameter(parameter)
        parameter =~ /^[0-9]+$/ ? parameter.to_i : nil
      end

      def pagination(items)
        limit = integer_parameter(params[:limit])
        offset = integer_parameter(params[:offset]) || 0
        unless limit.nil?
          headers['X-Pagination'] = Oj.dump(
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
        accepted!(Oj.dump(:issued => Time.now.to_i))
      end

      def no_content!
        status 204
        body ''
      end

      def event_hash(event_json, client_name, check_name)
        Oj.load(event_json).merge(
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
        $logger.info('publishing check result', {
          :payload => payload
        })
        $amq.direct('results').publish(Oj.dump(payload))
      end
    end

    before do
      request_log_line
      content_type 'application/json'
    end

    aget '/info' do
      response = {
        :sensu => {
          :version => VERSION
        },
        :rabbitmq => {
          :keepalives => {
            :messages => nil,
            :consumers => nil
          },
          :results => {
            :messages => nil,
            :consumers => nil
          },
          :connected => $rabbitmq.connected?
        },
        :redis => {
          :connected => $redis.connected?
        }
      }
      if $rabbitmq.connected?
        $amq.queue('keepalives').status do |messages, consumers|
          response[:rabbitmq][:keepalives][:messages] = messages
          response[:rabbitmq][:keepalives][:consumers] = consumers
          $amq.queue('results').status do |messages, consumers|
            response[:rabbitmq][:results][:messages] = messages
            response[:rabbitmq][:results][:consumers] = consumers
            body Oj.dump(response)
          end
        end
      else
        body Oj.dump(response)
      end
    end

    aget '/health' do
      if $redis.connected? && $rabbitmq.connected?
        healthy = Array.new
        min_consumers = integer_parameter(params[:consumers])
        max_messages = integer_parameter(params[:messages])
        $amq.queue('keepalives').status do |messages, consumers|
          if min_consumers
            healthy << (consumers >= min_consumers)
          end
          if max_messages
            healthy << (messages <= max_messages)
          end
          $amq.queue('results').status do |messages, consumers|
            if min_consumers
              healthy << (consumers >= min_consumers)
            end
            if max_messages
              healthy << (messages <= max_messages)
            end
            healthy.all? ? no_content! : unavailable!
          end
        end
      else
        unavailable!
      end
    end

    aget '/clients' do
      response = Array.new
      $redis.smembers('clients') do |clients|
        clients = pagination(clients)
        unless clients.empty?
          clients.each_with_index do |client_name, index|
            $redis.get('client:' + client_name) do |client_json|
              response << Oj.load(client_json)
              if index == clients.size - 1
                body Oj.dump(response)
              end
            end
          end
        else
          body Oj.dump(response)
        end
      end
    end

    aget %r{/clients?/([\w\.-]+)$} do |client_name|
      $redis.get('client:' + client_name) do |client_json|
        unless client_json.nil?
          body client_json
        else
          not_found!
        end
      end
    end

    aget %r{/clients/([\w\.-]+)/history$} do |client_name|
      response = Array.new
      $redis.smembers('history:' + client_name) do |checks|
        unless checks.empty?
          checks.each_with_index do |check_name, index|
            history_key = 'history:' + client_name + ':' + check_name
            $redis.lrange(history_key, -21, -1) do |history|
              history.map! do |status|
                status.to_i
              end
              execution_key = 'execution:' + client_name + ':' + check_name
              $redis.get(execution_key) do |last_execution|
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
                  body Oj.dump(response)
                end
              end
            end
          end
        else
          body Oj.dump(response)
        end
      end
    end

    adelete %r{/clients?/([\w\.-]+)$} do |client_name|
      $redis.get('client:' + client_name) do |client_json|
        unless client_json.nil?
          $redis.hgetall('events:' + client_name) do |events|
            events.each do |check_name, event_json|
              resolve_event(event_hash(event_json, client_name, check_name))
            end
            EM::Timer.new(5) do
              client = Oj.load(client_json)
              $logger.info('deleting client', {
                :client => client
              })
              $redis.srem('clients', client_name)
              $redis.del('events:' + client_name)
              $redis.del('client:' + client_name)
              $redis.smembers('history:' + client_name) do |checks|
                checks.each do |check_name|
                  $redis.del('history:' + client_name + ':' + check_name)
                  $redis.del('execution:' + client_name + ':' + check_name)
                end
                $redis.del('history:' + client_name)
              end
            end
            issued!
          end
        else
          not_found!
        end
      end
    end

    aget '/checks' do
      body Oj.dump($settings.checks)
    end

    aget %r{/checks?/([\w\.-]+)$} do |check_name|
      if $settings.check_exists?(check_name)
        response = $settings[:checks][check_name].merge(:name => check_name)
        body Oj.dump(response)
      else
        not_found!
      end
    end

    apost %r{/(?:check/)?request$} do
      begin
        post_body = Oj.load(request.body.read)
        check_name = post_body[:check]
        subscribers = post_body[:subscribers]
        if check_name.is_a?(String) && subscribers.is_a?(Array)
          if $settings.check_exists?(check_name)
            check = $settings[:checks][check_name]
            if subscribers.empty?
              subscribers = check[:subscribers] || Array.new
            end
            payload = {
              :name => check_name,
              :command => check[:command],
              :issued => Time.now.to_i
            }
            $logger.info('publishing check request', {
              :payload => payload,
              :subscribers => subscribers
            })
            subscribers.uniq.each do |exchange_name|
              $amq.fanout(exchange_name).publish(Oj.dump(payload))
            end
            issued!
          else
            not_found!
          end
        else
          bad_request!
        end
      rescue Oj::ParseError, TypeError
        bad_request!
      end
    end

    aget '/events' do
      response = Array.new
      $redis.smembers('clients') do |clients|
        unless clients.empty?
          clients.each_with_index do |client_name, index|
            $redis.hgetall('events:' + client_name) do |events|
              events.each do |check_name, event_json|
                response << event_hash(event_json, client_name, check_name)
              end
              if index == clients.size - 1
                body Oj.dump(response)
              end
            end
          end
        else
          body Oj.dump(response)
        end
      end
    end

    aget %r{/events/([\w\.-]+)$} do |client_name|
      response = Array.new
      $redis.hgetall('events:' + client_name) do |events|
        events.each do |check_name, event_json|
          response << event_hash(event_json, client_name, check_name)
        end
        body Oj.dump(response)
      end
    end

    aget %r{/events?/([\w\.-]+)/([\w\.-]+)$} do |client_name, check_name|
      $redis.hgetall('events:' + client_name) do |events|
        event_json = events[check_name]
        unless event_json.nil?
          body Oj.dump(event_hash(event_json, client_name, check_name))
        else
          not_found!
        end
      end
    end

    adelete %r{/events?/([\w\.-]+)/([\w\.-]+)$} do |client_name, check_name|
      $redis.hgetall('events:' + client_name) do |events|
        if events.include?(check_name)
          resolve_event(event_hash(events[check_name], client_name, check_name))
          issued!
        else
          not_found!
        end
      end
    end

    apost %r{/(?:event/)?resolve$} do
      begin
        post_body = Oj.load(request.body.read)
        client_name = post_body[:client]
        check_name = post_body[:check]
        if client_name.is_a?(String) && check_name.is_a?(String)
          $redis.hgetall('events:' + client_name) do |events|
            if events.include?(check_name)
              resolve_event(event_hash(events[check_name], client_name, check_name))
              issued!
            else
              not_found!
            end
          end
        else
          bad_request!
        end
      rescue Oj::ParseError, TypeError
        bad_request!
      end
    end

    aget '/aggregates' do
      response = Array.new
      $redis.smembers('aggregates') do |checks|
        unless checks.empty?
          checks.each_with_index do |check_name, index|
            $redis.smembers('aggregates:' + check_name) do |aggregates|
              aggregates.map! do |issued|
                issued.to_i
              end
              item = {
                :check => check_name,
                :issued => aggregates.sort.reverse
              }
              response << item
              if index == checks.size - 1
                body Oj.dump(response)
              end
            end
          end
        else
          body Oj.dump(response)
        end
      end
    end

    aget %r{/aggregates/([\w\.-]+)$} do |check_name|
      $redis.smembers('aggregates:' + check_name) do |aggregates|
        unless aggregates.empty?
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
          aggregates = pagination(aggregates.sort.reverse)
          body Oj.dump(aggregates)
        else
          not_found!
        end
      end
    end

    adelete %r{/aggregates/([\w\.-]+)$} do |check_name|
      $redis.smembers('aggregates:' + check_name) do |aggregates|
        unless aggregates.empty?
          aggregates.each do |check_issued|
            result_set = check_name + ':' + check_issued
            $redis.del('aggregation:' + result_set)
            $redis.del('aggregate:' + result_set)
          end
          $redis.del('aggregates:' + check_name) do
            $redis.srem('aggregates', check_name) do
              no_content!
            end
          end
        else
          not_found!
        end
      end
    end

    aget %r{/aggregates?/([\w\.-]+)/([\w\.-]+)$} do |check_name, check_issued|
      result_set = check_name + ':' + check_issued
      $redis.hgetall('aggregate:' + result_set) do |aggregate|
        unless aggregate.empty?
          response = aggregate.inject(Hash.new) do |totals, (status, count)|
            totals[status] = Integer(count)
            totals
          end
          $redis.hgetall('aggregation:' + result_set) do |results|
            parsed_results = results.inject(Array.new) do |parsed, (client_name, check_json)|
              check = Oj.load(check_json)
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
            body Oj.dump(response)
          end
        else
          not_found!
        end
      end
    end

    apost %r{/stash(?:es)?/(.*)} do |path|
      begin
        post_body = Oj.load(request.body.read)
        $redis.set('stash:' + path, Oj.dump(post_body)) do
          $redis.sadd('stashes', path) do
            created!(Oj.dump(:path => path))
          end
        end
      rescue Oj::ParseError
        bad_request!
      end
    end

    aget %r{/stash(?:es)?/(.*)} do |path|
      $redis.get('stash:' + path) do |stash_json|
        unless stash_json.nil?
          body stash_json
        else
          not_found!
        end
      end
    end

    adelete %r{/stash(?:es)?/(.*)} do |path|
      $redis.exists('stash:' + path) do |stash_exists|
        if stash_exists
          $redis.srem('stashes', path) do
            $redis.del('stash:' + path) do
              no_content!
            end
          end
        else
          not_found!
        end
      end
    end

    aget '/stashes' do
      response = Array.new
      $redis.smembers('stashes') do |stashes|
        stashes = pagination(stashes)
        unless stashes.empty?
          stashes.each_with_index do |path, index|
            $redis.get('stash:' + path) do |stash_json|
              unless stash_json.nil?
                item = {
                  :path => path,
                  :content => Oj.load(stash_json)
                }
                response << item
              end
              if index == stashes.size - 1
                body Oj.dump(response)
              end
            end
          end
        else
          body Oj.dump(response)
        end
      end
    end

    apost '/stashes' do
      begin
        post_body = Oj.load(request.body.read)
        path = post_body[:path]
        content = post_body[:content]
        if path.is_a?(String) && content.is_a?(Hash)
          $redis.set('stash:' + path, Oj.dump(content)) do
            $redis.sadd('stashes', path) do
              created!(Oj.dump(:path => path))
            end
          end
        else
          bad_request!
        end
      rescue Oj::ParseError
        bad_request!
      end
    end
  end
end
