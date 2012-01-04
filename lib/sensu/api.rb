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
      rabbitmq = AMQP.connect($settings.rabbitmq.to_hash.symbolize_keys)
      $amq = AMQP::Channel.new(rabbitmq)
    end

    before do
      content_type 'application/json'
    end

    aget '/clients' do
      $logger.debug('[clients] -- ' + request.ip + ' -- GET -- request for client list')
      response = Array.new
      $redis.smembers('clients').callback do |clients|
        unless clients.empty?
          clients.each_with_index do |client, index|
            $redis.get('client:' + client).callback do |client_json|
              response.push(JSON.parse(client_json))
              body response.to_json if index == clients.size - 1
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
        status 404 if client_json.nil?
        body client_json
      end
    end

    adelete '/client/:name' do |client|
      $logger.debug('[client] -- ' + request.ip + ' -- DELETE -- request for client -- ' + client)
      $redis.sismember('clients', client).callback do |client_exists|
        if client_exists
          $redis.hgetall('events:' + client).callback do |events|
            events.keys.each do |check_name|
              check = {
                :name => check_name,
                :issued => Time.now.to_i,
                :status => 0,
                :output => 'Client is being removed on request of the API',
                :force_resolve => true
              }
              $amq.queue('results').publish({:client => client, :check => check}.to_json)
            end
            EM::Timer.new(5) do
              $redis.srem('clients', client)
              $redis.del('events:' + client)
              $redis.del('client:' + client)
              $settings.checks.each_key do |check_name|
                $redis.del('history:' + client + ':' + check_name)
              end
            end
            status 204
            body nil
          end
        else
          status 404
          body nil
        end
      end
    end

    aget '/checks' do
      $logger.debug('[checks] -- ' + request.ip + ' -- GET -- request for check list')
      body $settings.checks.to_json
    end

    aget '/check/:name' do |check|
      $logger.debug('[check] -- ' + request.ip + ' -- GET -- request for check -- ' + check)
      if $settings.checks.key?(check)
        body $settings.checks[check].to_json
      else
        status 404
        body nil
      end
    end

    aget '/events' do
      $logger.debug('[events] -- ' + request.ip + ' -- GET -- request for event list')
      response = Hash.new
      $redis.smembers('clients').callback do |clients|
        unless clients.empty?
          clients.each_with_index do |client, index|
            $redis.hgetall('events:' + client).callback do |events|
              events.each do |key, value|
                events[key] = JSON.parse(value)
              end
              response[client] = events unless events.empty?
              body response.to_json if index == clients.size - 1
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
        event = events[check]
        status 404 if event.nil?
        body event
      end
    end

    apost '/event/resolve' do
      $logger.debug('[event] -- ' + request.ip + ' -- POST -- request to resolve event')
      begin
        event = JSON.parse(request.body.read)
      rescue JSON::ParserError
        status 400
        body nil
      end
      if event.has_key?('client') && event.has_key?('check')
        $redis.hgetall('events:' + event['client']).callback do |events|
          if events.has_key?(event['check'])
            check = {
              :name => event['check'],
              :issued => Time.now.to_i,
              :status => 0,
              :output => 'Resolving on request of the API',
              :force_resolve => true
            }
            $amq.queue('results').publish({:client => event['client'], :check => check}.to_json)
            status 201
          else
            status 404
          end
          body nil
        end
      else
        status 400
        body nil
      end
    end

    apost '/stash/*' do |path|
      $logger.debug('[stash] -- ' + request.ip + ' -- POST -- request for stash -- ' + path)
      begin
        stash = JSON.parse(request.body.read)
      rescue JSON::ParserError
        status 400
        body nil
      end
      $redis.set('stash:' + path, stash.to_json).callback do
        $redis.sadd('stashes', path).callback do
          status 201
          body nil
        end
      end
    end

    aget '/stash/*' do |path|
      $logger.debug('[stash] -- ' + request.ip + ' -- GET -- request for stash -- ' + path)
      $redis.get('stash:' + path).callback do |stash|
        status 404 if stash.nil?
        body stash
      end
    end

    adelete '/stash/*' do |path|
      $logger.debug('[stash] -- ' + request.ip + ' -- DELETE -- request for stash -- ' + path)
      $redis.exists('stash:' + path).callback do |stash_exist|
        if stash_exist
          $redis.srem('stashes', path).callback do
            $redis.del('stash:' + path).callback do
              status 204
              body nil
            end
          end
        else
          status 404
          body nil
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
        paths = JSON.parse(request.body.read)
      rescue JSON::ParserError
        status 400
        body nil
      end
      response = Hash.new
      if paths.is_a?(Array) && paths.size > 0
        paths.each_with_index do |path, index|
          $redis.get('stash:' + path).callback do |stash|
            response[path] = JSON.parse(stash) unless stash.nil?
            body response.to_json if index == paths.size - 1
          end
        end
      else
        status 400
        body nil
      end
    end

    def self.setup_test_scaffolding(options={})
      self.setup(options)
      $settings.client.timestamp = Time.now.to_i
      $redis.set('client:' + $settings.client.name, $settings.client.to_json).callback do
        $redis.sadd('clients', $settings.client.name).callback do
          $redis.hset('events:' + $settings.client.name, 'test', {
            :status => 2,
            :output => 'CRITICAL',
            :flapping => false,
            :occurrences => 1
          }.to_json).callback do
            $redis.set('stash:test/test', '{"key": "value"}').callback do
              Thin::Logging.silent = true
              Thin::Server.start(self, $settings.api.port)
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
