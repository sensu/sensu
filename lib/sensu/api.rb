require File.join(File.dirname(__FILE__), 'config')
require 'sinatra/async'
require 'em-hiredis'

module Sensu
  class API < Sinatra::Base
    register Sinatra::Async

    def self.run(options={})
      EM.run do
        self.setup(options)
        self.run!(:port => @settings['api']['port'])

        Signal.trap('INT') do
          EM.stop
        end

        Signal.trap('TERM') do
          EM.stop
        end
      end
    end

    def self.setup(options={})
      config = Sensu::Config.new(options)
      @settings = config.settings
      set :redis, EM::Hiredis.connect('redis://' + @settings['redis']['host'] + ':' + @settings['redis']['port'].to_s)
      connection = AMQP.connect(symbolize_keys(@settings['rabbitmq']))
      set :amq, AMQP::Channel.new(connection)
    end

    helpers do
      include Rack::Utils
      alias_method :conn, :settings
    end

    before do
      content_type 'application/json'
    end

    aget '/clients' do
      current_clients = Array.new
      conn.redis.smembers('clients').callback do |clients|
        unless clients.empty?
          clients.each_with_index do |client, index|
            conn.redis.get('client:' + client).callback do |client_json|
              current_clients.push(JSON.parse(client_json))
              body current_clients.to_json if index == clients.size-1
            end
          end
        else
          body current_clients.to_json
        end
      end
    end

    aget '/client/:id' do |client|
      conn.redis.get('client:' + client).callback do |client_json|
        status 404 if client_json.nil?
        body client_json
      end
    end

    aget '/events' do
      current_events = Hash.new
      conn.redis.smembers('clients').callback do |clients|
        unless clients.empty?
          clients.each_with_index do |client, index|
            conn.redis.hgetall('events:' + client).callback do |events|
              client_events = Hash[*events]
              client_events.each do |key, value|
                client_events[key] = JSON.parse(value)
              end
              current_events.store(client, client_events) unless client_events.empty?
              body current_events.to_json if index == clients.size-1
            end
          end
        else
          body current_events.to_json
        end
      end
    end

    adelete '/client/:id' do |client|
      conn.redis.sismember('clients', client).callback do |client_exists|
        unless client_exists == 0
          conn.redis.exists('events:' + client).callback do |events_exist|
            unless events_exist == 0
              conn.redis.hgetall('events:' + client).callback do |events|
                Hash[*events].keys.each do |check|
                  conn.amq.queue('results').publish({'check' => check, 'client' => client, 'status' => 0, 'output' => 'client is being removed...'}.to_json)
                end
                EM.add_timer(10) do
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
            body ''
          end
        else
          status 404
          body ''
        end
      end
    end

    apost '/test/client' do
      client = '{
        "name": "test",
        "address": "127.0.0.1",
        "subscriptions": [
          "foo",
          "bar"
        ]
      }'
      conn.redis.set('client:test', client).callback do
        conn.redis.sadd('clients', 'test')
        status 201
        body ''
      end
    end

    apost '/test/event' do
      conn.redis.hset('events:test', 'test', {'status' => 2, 'output' => 'CRITICAL :: test'}.to_json).callback do
        status 201
        body ''
      end
    end
  end
end
