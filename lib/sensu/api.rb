require File.join(File.dirname(__FILE__), 'config')

require 'thin'
require 'sinatra/async'
require 'redis'

require File.join(File.dirname(__FILE__), 'patches', 'redis')

module Sensu
  class API < Sinatra::Base
    register Sinatra::Async

    def self.run(options={})
      EM::run do
        self.setup(options)

        Thin::Logging.silent = true
        Thin::Server.start(self, $settings.api.port)

        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            self.stop(signal)
          end
        end
      end
    end

    def self.setup(options={})
      config = Sensu::Config.new(options)
      $logger = config.logger
      $settings = config.settings
      if options[:daemonize]
        Process.daemonize
      end
      if options[:pid_file]
        Process.write_pid(options[:pid_file])
      end
      $logger.debug('[setup] -- connecting to redis')
      $redis = Redis.connect($settings.redis.to_hash.symbolize_keys)
      $logger.debug('[setup] -- connecting to rabbitmq')
      $rabbitmq = AMQP.connect($settings.rabbitmq.to_hash.symbolize_keys)
      $amq = AMQP::Channel.new($rabbitmq)
      if $settings.api.user && $settings.api.password
        use Rack::Auth::Basic do |user, password|
          user == $settings.api.user && password == $settings.api.password
        end
      end
    end

    configure do
      disable :protection
    end

    not_found do
      ''
    end

    before do
      content_type 'application/json'
    end

    aget '/info' do
      $logger.debug('[info] -- ' + request.ip + ' -- GET -- request for sensu info')
      response = {
        :sensu => {
          :version => VERSION
        },
        :health => {
          :redis => 'ok',
          :rabbitmq => 'ok'
        }
      }
      if $redis.reconnecting?
        response[:health][:redis] = 'down'
      end
      if $rabbitmq.reconnecting?
        response[:health][:rabbitmq] = 'down'
      end
      body response.to_json
    end

    aget '/clients' do
      $logger.debug('[clients] -- ' + request.ip + ' -- GET -- request for client list')
      response = Array.new
      $redis.smembers('clients').callback do |clients|
        unless clients.empty?
          clients.each_with_index do |client, index|
            $redis.get('client:' + client).callback do |client_json|
              response.push(JSON.parse(client_json))
              if index == clients.size - 1
                body response.to_json
              end
            end
          end
        else
          body response.to_json
        end
      end
    end

    aget '/client/:name' do |client|
      $logger.debug('[client] -- ' + request.ip + ' -- GET -- request for client -- ' + client)
      $redis.get('client:' + client).callback do |client_json|
        unless client_json.nil?
          body client_json
        else
          status 404
          body ''
        end
      end
    end

    adelete '/client/:name' do |client|
      $logger.debug('[client] -- ' + request.ip + ' -- DELETE -- request for client -- ' + client)
      $redis.sismember('clients', client).callback do |client_exists|
        if client_exists
          $redis.hgetall('events:' + client).callback do |events|
            events.keys.each do |check_name|
              $logger.info('[client] -- publishing check result to resolve event -- ' + client + ' -- ' + check_name)
              check = {
                :name => check_name,
                :output => 'Client is being removed on request of the API',
                :status => 0,
                :issued => Time.now.to_i,
                :force_resolve => true
              }
              $amq.queue('results').publish({:client => client, :check => check}.to_json)
            end
            $logger.info('[client] -- client will be deleted -- ' + client)
            EM::Timer.new(5) do
              $logger.info('[client] -- deleting client -- ' + client)
              $redis.srem('clients', client)
              $redis.del('events:' + client)
              $redis.del('client:' + client)
              $settings.checks.each_key do |check_name|
                $redis.del('history:' + client + ':' + check_name)
              end
            end
            status 204
            body ''
          end
        else
          status 404
          body ''
        end
      end
    end

    aget '/checks' do
      $logger.debug('[checks] -- ' + request.ip + ' -- GET -- request for check list')
      response = $settings.checks.map { |check, details| details.merge(:name => check) }
      body response.to_json
    end

    aget '/check/:name' do |check|
      $logger.debug('[check] -- ' + request.ip + ' -- GET -- request for check -- ' + check)
      if $settings.checks.key?(check)
        response = $settings.checks[check].merge(:name => check)
        body response.to_json
      else
        status 404
        body ''
      end
    end

    apost '/check/request' do
      $logger.debug('[check] -- ' + request.ip + ' -- POST -- request to publish a check request')
      begin
        post_body = Hashie::Mash.new(JSON.parse(request.body.read))
      rescue JSON::ParserError
        status 400
        body ''
      end
      if post_body.check.is_a?(String) && post_body.subscribers.is_a?(Array)
        post_body.subscribers.each do |exchange|
          $logger.info('[check] -- publishing check request -- ' + post_body.check + ' -- ' + exchange)
          $amq.fanout(exchange).publish({:name => post_body.check, :issued => Time.now.to_i}.to_json)
        end
        status 201
      else
        status 400
      end
      body ''
    end

    aget '/events' do
      $logger.debug('[events] -- ' + request.ip + ' -- GET -- request for event list')
      response = Array.new
      $redis.smembers('clients').callback do |clients|
        unless clients.empty?
          clients.each_with_index do |client, index|
            $redis.hgetall('events:' + client).callback do |events|
              events.each do |check, details|
                response.push(JSON.parse(details).merge(:client => client, :check => check))
              end
              if index == clients.size - 1
                body response.to_json
              end
            end
          end
        else
          body response.to_json
        end
      end
    end

    aget '/event/:client/:check' do |client, check|
      $logger.debug('[event] -- ' + request.ip + ' -- GET -- request for event -- ' + client + ' -- ' + check)
      $redis.hgetall('events:' + client).callback do |events|
        event_json = events[check]
        unless event_json.nil?
          response = JSON.parse(event_json).merge(:client => client, :check => check)
          body response.to_json
        else
          status 404
          body ''
        end
      end
    end

    apost '/event/resolve' do
      $logger.debug('[event] -- ' + request.ip + ' -- POST -- request to resolve event')
      begin
        post_body = Hashie::Mash.new(JSON.parse(request.body.read))
      rescue JSON::ParserError
        status 400
        body ''
      end
      if post_body.client.is_a?(String) && post_body.check.is_a?(String)
        $redis.hgetall('events:' + post_body.client).callback do |events|
          if events.include?(post_body.check)
            $logger.info('[event] -- publishing check result to resolve event -- ' + post_body.client + ' -- ' + post_body.check)
            check = {
              :name => post_body.check,
              :output => 'Resolving on request of the API',
              :status => 0,
              :issued => Time.now.to_i,
              :force_resolve => true
            }
            $amq.queue('results').publish({:client => post_body.client, :check => check}.to_json)
            status 201
          else
            status 404
          end
          body ''
        end
      else
        status 400
        body ''
      end
    end

    apost '/stash/*' do |path|
      $logger.debug('[stash] -- ' + request.ip + ' -- POST -- request for stash -- ' + path)
      begin
        post_body = JSON.parse(request.body.read)
      rescue JSON::ParserError
        status 400
        body ''
      end
      $redis.set('stash:' + path, post_body.to_json).callback do
        $redis.sadd('stashes', path).callback do
          status 201
          body ''
        end
      end
    end

    aget '/stash/*' do |path|
      $logger.debug('[stash] -- ' + request.ip + ' -- GET -- request for stash -- ' + path)
      $redis.get('stash:' + path).callback do |stash_json|
        if stash_json.nil?
          status 404
          body ''
        else
          body stash_json
        end
      end
    end

    adelete '/stash/*' do |path|
      $logger.debug('[stash] -- ' + request.ip + ' -- DELETE -- request for stash -- ' + path)
      $redis.exists('stash:' + path).callback do |stash_exists|
        if stash_exists
          $redis.srem('stashes', path).callback do
            $redis.del('stash:' + path).callback do
              status 204
              body ''
            end
          end
        else
          status 404
          body ''
        end
      end
    end

    aget '/stashes' do
      $logger.debug('[stashes] -- ' + request.ip + ' -- GET -- request for list of stashes')
      $redis.smembers('stashes') do |stashes|
        body stashes.to_json
      end
    end

    apost '/stashes' do
      $logger.debug('[stashes] -- ' + request.ip + ' -- POST -- request for multiple stashes')
      begin
        post_body = JSON.parse(request.body.read)
      rescue JSON::ParserError
        status 400
        body ''
      end
      response = Hash.new
      if post_body.is_a?(Array) && post_body.size > 0
        post_body.each_with_index do |path, index|
          $redis.get('stash:' + path).callback do |stash_json|
            unless stash_json.nil?
              response[path] = JSON.parse(stash_json)
            end
            if index == post_body.size - 1
              body response.to_json
            end
          end
        end
      else
        status 400
        body ''
      end
    end

    def self.run_test(options={}, &block)
      self.setup(options)
      $settings.client.timestamp = Time.now.to_i
      $redis.set('client:' + $settings.client.name, $settings.client.to_json).callback do
        $redis.sadd('clients', $settings.client.name).callback do
          $redis.hset('events:' + $settings.client.name, 'test', {
            :output => "CRITICAL\n",
            :status => 2,
            :issued => Time.now.utc.iso8601,
            :flapping => false,
            :occurrences => 1
          }.to_json).callback do
            $redis.set('stash:test/test', '{"key": "value"}').callback do
              $redis.sadd('stashes', 'test/test').callback do
                Thin::Logging.silent = true
                Thin::Server.start(self, $settings.api.port)
                block.call
              end
            end
          end
        end
      end
    end

    def self.stop(signal)
      $logger.warn('[stop] -- stopping sensu api -- ' + signal)
      $logger.warn('[stop] -- stopping reactor')
      EM::PeriodicTimer.new(0.25) do
        EM::stop_event_loop
      end
    end
  end
end
