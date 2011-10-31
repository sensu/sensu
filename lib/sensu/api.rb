require File.join(File.dirname(__FILE__), 'config')
require 'sinatra/async'
require 'em-hiredis'

module Sensu
  class API < Sinatra::Base
    register Sinatra::Async

    def self.run(options={})
      EM.run do
        self.setup(options)
        self.run!(:port => @settings.api.port)

        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            EM.warning('[process] -- ' + signal + ' -- stopping sensu api')
            EM.add_timer(1) do
              EM.stop
            end
          end
        end
      end
    end

    def self.setup(options={})
      config = Sensu::Config.new(options)
      @settings = config.settings
      EM.syslog_setup(@settings.syslog.host, @settings.syslog.port)
      EM.debug('[setup] -- connecting to redis')
      set :redis, EM::Hiredis.connect('redis://' + @settings.redis.host + ':' + @settings.redis.port.to_s)
      EM.debug('[setup] -- connecting to rabbitmq')
      connection = AMQP.connect(@settings.rabbitmq.to_hash.symbolize_keys)
      set :amq, MQ.new(connection)
    end

    helpers do
      include Rack::Utils
      alias_method :conn, :settings
    end

    before do
      content_type 'application/json'
    end

    aget '/clients' do
      EM.debug('[clients] -- ' + request.ip + ' -- GET -- request for client list')
      current_clients = Array.new
      conn.redis.smembers('clients').callback do |clients|
        unless clients.empty?
          clients.each_with_index do |client, index|
            conn.redis.get('client:' + client).callback do |client_json|
              current_clients.push(JSON.parse(client_json))
              body current_clients.to_json if index == clients.size - 1
            end
          end
        else
          body current_clients.to_json
        end
      end
    end

    aget '/client/:name' do |client|
      EM.debug('[client] -- ' + request.ip + ' -- GET -- request for client -- ' + client)
      conn.redis.get('client:' + client).callback do |client_json|
        status 404 if client_json.nil?
        body client_json
      end
    end

    adelete '/client/:name' do |client|
      EM.debug('[client] -- ' + request.ip + ' -- DELETE -- request for client -- ' + client)
      conn.redis.sismember('clients', client).callback do |client_exists|
        unless client_exists == 0
          conn.redis.exists('events:' + client).callback do |events_exist|
            unless events_exist == 0
              conn.redis.hgetall('events:' + client).callback do |events|
                Hash[*events].keys.each do |check_name|
                  check = {:name => check_name, :issued => Time.now.to_i, :status => 0, :output => 'Client is being removed'}
                  conn.amq.queue('results').publish({:client => client, :check => check}.to_json)
                end
                EM.add_timer(5) do
                  conn.redis.srem('clients', client)
                  conn.redis.del('events:' + client)
                  conn.redis.del('client:' + client)
                end
              end
            else
              conn.redis.srem('clients', client)
              conn.redis.del('events:' + client)
              conn.redis.del('client:' + client)
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

    aget '/events' do
      EM.debug('[events] -- ' + request.ip + ' -- GET -- request for event list')
      current_events = Hash.new
      conn.redis.smembers('clients').callback do |clients|
        unless clients.empty?
          clients.each_with_index do |client, index|
            conn.redis.hgetall('events:' + client).callback do |events|
              client_events = Hash[*events]
              client_events.each do |key, value|
                client_events[key] = JSON.parse(value)
              end
              current_events[client] = client_events unless client_events.empty?
              body current_events.to_json if index == clients.size - 1
            end
          end
        else
          body current_events.to_json
        end
      end
    end

    aget '/event/:client/:check' do |client, check|
      EM.debug('[event] -- ' + request.ip + ' -- GET -- request for event -- ' + client + ' -- ' + check)
      conn.redis.hgetall('events:' + client).callback do |events|
        client_events = Hash[*events]
        event = client_events[check]
        status 404 if event.nil?
        body event
      end
    end

    apost '/stash/*' do |path|
      EM.debug('[stash] -- ' + request.ip + ' -- POST -- request for stash -- ' + path)
      begin
        stash = JSON.parse(request.body.read)
      rescue JSON::ParserError
        status 400
        body nil
      end
      conn.redis.set('stash:' + path, stash.to_json).callback do
        status 201
        body nil
      end
    end

    apost '/stashes' do
      EM.debug('[stashes] -- ' + request.ip + ' -- POST -- request for multiple stashes')
      begin
        paths = JSON.parse(request.body.read)
      rescue JSON::ParserError
        status 400
        body nil
      end
      stashes = Hash.new
      if paths.is_a?(Array)
        paths.each_with_index do |path, index|
          conn.redis.get('stash:' + path).callback do |stash|
            stashes[path] = JSON.parse(stash) unless stash.nil?
            body stashes.to_json if index == paths.size - 1
          end
        end
      else
        status 400
        body nil
      end
    end

    aget '/stash/*' do |path|
      EM.debug('[stash] -- ' + request.ip + ' -- GET -- request for stash -- ' + path)
      conn.redis.get('stash:' + path).callback do |stash|
        status 404 if stash.nil?
        body stash
      end
    end

    adelete '/stash/*' do |path|
      EM.debug('[stash] -- ' + request.ip + ' -- DELETE -- request for stash -- ' + path)
      conn.redis.exists('stash:' + path).callback do |stash_exist|
        unless stash_exist == 0
          conn.redis.del('stash:' + path).callback do
            status 204
            body nil
          end
        else
          status 404
          body nil
        end
      end
    end

    apost '/test' do
      EM.debug('[test] -- ' + request.ip + ' -- POST -- seeding for minitest')
      client = '{
        "name": "test",
        "address": "localhost",
        "subscriptions": [
          "foo",
          "bar"
        ]
      }'
      conn.redis.set('client:test', client).callback do
        conn.redis.sadd('clients', 'test').callback do
          conn.redis.hset('events:test', 'test', {
            :status => 2,
            :output => 'CRITICAL',
            :flapping => false,
            :occurrences => 1
          }.to_json).callback do
            conn.redis.set('stash:test/test', '{"key": "value"}').callback do
              status 201
              body nil
            end
          end
        end
      end
    end
  end
end
