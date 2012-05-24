require File.join(File.dirname(__FILE__), 'base')
require File.join(File.dirname(__FILE__), 'redis')

require 'thin'
require 'sinatra/async'

module Sensu
  class API < Sinatra::Base
    register Sinatra::Async

    def self.run(options={})
      EM::run do
        self.setup(options)

        Thin::Logging.silent = true
        Thin::Server.start(self, $settings[:api][:port])

        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            self.stop(signal)
          end
        end
      end
    end

    def self.setup(options={})
      $logger = Cabin::Channel.get
      base = Sensu::Base.new(options)
      $settings = base.settings
      $logger.debug('connecting to redis', {
        :settings => $settings[:redis]
      })
      $redis = Sensu::Redis.connect($settings[:redis])
      $redis.on_disconnect = Proc.new do
        $logger.warn('reconnecting to redis')
        $redis.reconnect!
      end
      $logger.debug('connecting to rabbitmq', {
        :settings => $settings[:rabbitmq]
      })
      $rabbitmq = AMQP.connect($settings[:rabbitmq])
      $amq = AMQP::Channel.new($rabbitmq)
      if $settings[:api][:user] && $settings[:api][:password]
        use Rack::Auth::Basic do |user, password|
          user == $settings[:api][:user] && password == $settings[:api][:password]
        end
      end
    end

    def healthy?
      unless $redis.connected?
        unless env['REQUEST_PATH'] == '/info'
          halt 500
        end
      end
    end

    def request_log
      $logger.info([env['REQUEST_METHOD'], env['REQUEST_PATH']].join(' '), {
        :remote_address => env['REMOTE_ADDR'],
        :user_agent => env['HTTP_USER_AGENT'],
        :request_method => env['REQUEST_METHOD'],
        :request_uri => env['REQUEST_URI'],
        :request_body =>  env['rack.input'].read
      })
      env['rack.input'].rewind
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

    before do
      content_type 'application/json'
      request_log
      healthy?
    end

    aget '/info' do
      response = {
        :sensu => {
          :version => Sensu::VERSION
        },
        :health => {
          :redis => $redis.connected? ? 'ok' : 'down',
          :rabbitmq => $rabbitmq.connected? ? 'ok' : 'down'
        }
      }
      body response.to_json
    end

    aget '/clients' do
      response = Array.new
      $redis.smembers('clients').callback do |clients|
        unless clients.empty?
          clients.each_with_index do |client_name, index|
            $redis.get('client:' + client_name).callback do |client_json|
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

    aget '/client/:name' do |client_name|
      $redis.get('client:' + client_name).callback do |client_json|
        unless client_json.nil?
          body client_json
        else
          status 404
          body ''
        end
      end
    end

    adelete '/client/:name' do |client_name|
      $redis.get('client:' + client_name).callback do |client_json|
        unless client_json.nil?
          client = JSON.parse(client_json, :symbolize_names => true)
          $logger.info('deleting client', {
            :client => client
          })
          $redis.hgetall('events:' + client_name).callback do |events|
            events.each_key do |check_name|
              payload = {
                :client => client_name,
                :check => {
                  :name => check_name,
                  :output => 'Client is being removed on request of the API',
                  :status => 0,
                  :issued => Time.now.to_i,
                  :force_resolve => true
                }
              }
              $logger.info('publishing check result', {
                :payload => payload
              })
              $amq.queue('results').publish(payload.to_json)
            end
            EM::Timer.new(5) do
              $redis.srem('clients', client_name)
              $redis.del('events:' + client_name)
              $redis.del('client:' + client_name)
              $redis.smembers('history:' + client_name).callback do |checks|
                checks.each do |check_name|
                  $redis.del('history:' + client_name + ':' + check_name)
                end
                $redis.del('history:' + client_name)
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
      body $settings.checks.to_json
    end

    aget '/check/:name' do |check_name|
      if $settings.check_exists?(check_name)
        response = $settings[:checks][check_name].merge(:name => check_name)
        body response.to_json
      else
        status 404
        body ''
      end
    end

    apost '/check/request' do
      begin
        post_body = JSON.parse(request.body.read, :symbolize_names => true)
      rescue JSON::ParserError
        status 400
        body ''
      end
      if post_body.is_a?(Hash) && post_body[:check].is_a?(String) && post_body[:subscribers].is_a?(Array)
        payload = {
          :name => post_body[:check],
          :issued => Time.now.to_i
        }
        $logger.info('publishing check request', {
          :payload => payload,
          :subscribers => post_body[:subscribers]
        })
        post_body[:subscribers].uniq.each do |exchange_name|
          $amq.fanout(exchange_name).publish(payload.to_json)
        end
        status 201
      else
        status 400
      end
      body ''
    end

    aget '/events' do
      response = Array.new
      $redis.smembers('clients').callback do |clients|
        unless clients.empty?
          clients.each_with_index do |client_name, index|
            $redis.hgetall('events:' + client_name).callback do |events|
              events.each do |check_name, event_json|
                response.push(JSON.parse(event_json).merge(:client => client_name, :check => check_name))
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

    aget '/event/:client/:check' do |client_name, check_name|
      $redis.hgetall('events:' + client_name).callback do |events|
        event_json = events[check_name]
        unless event_json.nil?
          response = JSON.parse(event_json).merge(:client => client_name, :check => check_name)
          body response.to_json
        else
          status 404
          body ''
        end
      end
    end

    apost '/event/resolve' do
      begin
        post_body = JSON.parse(request.body.read, :symbolize_names => true)
      rescue JSON::ParserError
        status 400
        body ''
      end
      if post_body.is_a?(Hash) && post_body[:client].is_a?(String) && post_body[:check].is_a?(String)
        $redis.hgetall('events:' + post_body[:client]).callback do |events|
          if events.include?(post_body[:check])
            payload = {
              :client => post_body[:client],
              :check => {
                :name => post_body[:check],
                :output => 'Resolving on request of the API',
                :status => 0,
                :issued => Time.now.to_i,
                :force_resolve => true
              }
            }
            $logger.info('publishing check result', {
              :payload => payload
            })
            $amq.queue('results').publish(payload.to_json)
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
      $redis.smembers('stashes') do |stashes|
        body stashes.to_json
      end
    end

    apost '/stashes' do
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
      $settings[:client][:timestamp] = Time.now.to_i
      $redis.set('client:' + $settings[:client][:name], $settings[:client].to_json).callback do
        $redis.sadd('clients', $settings[:client][:name]).callback do
          $redis.hset('events:' + $settings[:client][:name], 'test', {
            :output => "CRITICAL\n",
            :status => 2,
            :issued => Time.now.to_i,
            :flapping => false,
            :occurrences => 1
          }.to_json).callback do
            $redis.set('stash:test/test', '{"key": "value"}').callback do
              $redis.sadd('stashes', 'test/test').callback do
                Thin::Logging.silent = true
                Thin::Server.start(self, $settings[:api][:port])
                block.call
              end
            end
          end
        end
      end
    end

    def self.stop(signal)
      $logger.warn('received signal', {
        :signal => signal
      })
      $logger.warn('stopping')
      $redis.close
      $logger.warn('stopping reactor')
      EM::stop_event_loop
    end
  end
end
