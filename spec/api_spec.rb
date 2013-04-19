require 'em-http-request'

require File.dirname(__FILE__) + '/../lib/sensu/api.rb'
require File.dirname(__FILE__) + '/../lib/sensu/server.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::API' do
  include Helpers

  before do
    async_wrapper do
      client = client_template
      client[:timestamp] = epoch
      redis.flushdb do
        redis.set('client:i-424242', Oj.dump(client)) do
          redis.sadd('clients', 'i-424242') do
            redis.hset('events:i-424242', 'test', Oj.dump(
              :output => 'CRITICAL',
              :status => 2,
              :issued => Time.now.to_i,
              :flapping => false,
              :occurrences => 1
            )) do
              redis.set('stash:test/test', '{"key": "value"}') do
                redis.sadd('stashes', 'test/test') do
                  redis.sadd('history:i-424242', 'success') do
                    redis.sadd('history:i-424242', 'fail') do
                      redis.set('execution:i-424242:success', 1363224805) do
                        redis.set('execution:i-424242:fail', 1363224806) do
                          redis.rpush('history:i-424242:success', 0) do
                            @redis = nil
                            async_done
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  it 'can provide basic version and health information' do
    api_test do
      api_request('/info') do |http, body|
        http.response_header.status.should eq(200)
        body[:sensu][:version].should eq(Sensu::VERSION)
        body[:redis][:connected].should be_true
        body[:rabbitmq][:connected].should be_true
        body[:rabbitmq][:keepalives][:messages].should be_kind_of(Integer)
        body[:rabbitmq][:keepalives][:consumers].should be_kind_of(Integer)
        body[:rabbitmq][:results][:messages].should be_kind_of(Integer)
        body[:rabbitmq][:results][:consumers].should be_kind_of(Integer)
        async_done
      end
    end
  end

  it 'can provide connection and queue monitoring' do
    api_test do
      api_request('/health?consumers=0&messages=1000') do |http, body|
        http.response_header.status.should eq(204)
        body.should be_empty
        api_request('/health?consumers=1000') do |http, body|
          http.response_header.status.should eq(503)
          body.should be_empty
          api_request('/health?consumers=1000&messages=1000') do |http, body|
            http.response_header.status.should eq(503)
            async_done
          end
        end
      end
    end
  end

  it 'can provide current events' do
    api_test do
      api_request('/events') do |http, body|
        http.response_header.status.should eq(200)
        body.should be_kind_of(Array)
        test_event = Proc.new do |event|
          event[:check] == 'test'
        end
        body.should contain(test_event)
        async_done
      end
    end
  end

  it 'can provide current events for a specific client' do
    api_test do
      api_request('/events/i-424242') do |http, body|
        http.response_header.status.should eq(200)
        body.should be_kind_of(Array)
        test_event = Proc.new do |event|
          event[:check] == 'test'
        end
        body.should contain(test_event)
        async_done
      end
    end
  end

  it 'can provide current clients' do
    api_test do
      api_request('/clients') do |http, body|
        http.response_header.status.should eq(200)
        body.should be_kind_of(Array)
        test_client = Proc.new do |client|
          client[:name] == 'i-424242'
        end
        body.should contain(test_client)
        async_done
      end
    end
  end

  it 'can provide defined checks' do
    api_test do
      api_request('/checks') do |http, body|
        http.response_header.status.should eq(200)
        body.should be_kind_of(Array)
        test_check = Proc.new do |check|
          check[:name] == 'tokens'
        end
        body.should contain(test_check)
        async_done
      end
    end
  end

  it 'can provide a specific event' do
    api_test do
      api_request('/event/i-424242/test') do |http, body|
        http.response_header.status.should eq(200)
        body.should be_kind_of(Hash)
        body[:client].should eq('i-424242')
        body[:check].should eq('test')
        body[:output].should eq('CRITICAL')
        body[:status].should eq(2)
        body[:flapping].should be_false
        body[:occurrences].should eq(1)
        body[:issued].should be_within(10).of(epoch)
        async_done
      end
    end
  end

  it 'can not provide a nonexistent event' do
    api_test do
      api_request('/event/i-424242/nonexistent') do |http, body|
        http.response_header.status.should eq(404)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can delete an event' do
    api_test do
      result_queue do |queue|
        api_request('/event/i-424242/test', :delete) do |http, body|
          http.response_header.status.should eq(202)
          body.should include(:issued)
          queue.subscribe do |payload|
            result = Oj.load(payload)
            result[:client].should eq('i-424242')
            result[:check][:name].should eq('test')
            result[:check][:status].should eq(0)
            async_done
          end
        end
      end
    end
  end

  it 'can not delete a nonexistent event' do
    api_test do
      api_request('/event/i-424242/nonexistent', :delete) do |http, body|
        http.response_header.status.should eq(404)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can resolve an event' do
    api_test do
      result_queue do |queue|
        options = {
          :body => {
            :client => 'i-424242',
            :check => 'test'
          }
        }
        api_request('/resolve', :post, options) do |http, body|
          http.response_header.status.should eq(202)
          body.should include(:issued)
          queue.subscribe do |payload|
            result = Oj.load(payload)
            result[:client].should eq('i-424242')
            result[:check][:name].should eq('test')
            result[:check][:status].should eq(0)
            async_done
          end
        end
      end
    end
  end

  it 'can not resolve a nonexistent event' do
    api_test do
      options = {
        :body => {
          :client => 'i-424242',
          :check => 'nonexistent'
        }
      }
      api_request('/resolve', :post, options) do |http, body|
        http.response_header.status.should eq(404)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can not resolve an event with an invalid post body' do
    api_test do
      options = {
        :body => 'i-424242/test'
      }
      api_request('/resolve', :post, options) do |http, body|
        http.response_header.status.should eq(400)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can not resolve an event when missing data' do
    api_test do
      options = {
        :body => {
          :client => 'i-424242'
        }
      }
      api_request('/resolve', :post, options) do |http, body|
        http.response_header.status.should eq(400)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can provide a specific client' do
    api_test do
      api_request('/client/i-424242') do |http, body|
        http.response_header.status.should eq(200)
        body.should be_kind_of(Hash)
        body[:name].should eq('i-424242')
        body[:address].should eq('127.0.0.1')
        body[:subscriptions].should eq(['test'])
        body[:timestamp].should be_within(10).of(epoch)
        async_done
      end
    end
  end

  it 'can not provide a nonexistent client' do
    api_test do
      api_request('/client/nonexistent') do |http, body|
        http.response_header.status.should eq(404)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can request check history for a client' do
    api_test do
      api_request('/clients/i-424242/history') do |http, body|
        http.response_header.status.should eq(200)
        body.should be_kind_of(Array)
        body.should have(1).items
        body[0][:check].should eq('success')
        body[0][:history].should be_kind_of(Array)
        body[0][:last_execution].should eq(1363224805)
        body[0][:last_status].should eq(0)
        async_done
      end
    end
  end

  it 'can delete a client' do
    api_test do
      api_request('/client/i-424242', :delete) do |http, body|
        http.response_header.status.should eq(202)
        body.should include(:issued)
        async_done
      end
    end
  end

  it 'can not delete a noexistent client' do
    api_test do
      api_request('/client/nonexistent', :delete) do |http, body|
        http.response_header.status.should eq(404)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can provide a specific defined check' do
    api_test do
      api_request('/check/tokens') do |http, body|
        http.response_header.status.should eq(200)
        body.should be_kind_of(Hash)
        body[:name].should eq('tokens')
        body[:interval].should eq(1)
        async_done
      end
    end
  end

  it 'can not provide a nonexistent defined check' do
    api_test do
      api_request('/check/nonexistent') do |http, body|
        http.response_header.status.should eq(404)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can issue a check request' do
    api_test do
      options = {
        :body => {
          :check => 'tokens',
          :subscribers => [
            'test'
          ]
        }
      }
      api_request('/request', :post, options) do |http, body|
        http.response_header.status.should eq(202)
        body.should include(:issued)
        async_done
      end
    end
  end

  it 'can not issue a check request with an invalid post body' do
    api_test do
      options = {
        :body => {
          :check => 'tokens',
          :subscribers => 'invalid'
        }
      }
      api_request('/request', :post, options) do |http, body|
        http.response_header.status.should eq(400)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can not issue a check request when missing data' do
    api_test do
      options = {
        :body => {
          :check => 'tokens'
        }
      }
      api_request('/request', :post, options) do |http, body|
        http.response_header.status.should eq(400)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can not issue a check request for a nonexistent defined check' do
    api_test do
      options = {
        :body => {
          :check => 'nonexistent',
          :subscribers => [
            'test'
          ]
        }
      }
      api_request('/request', :post, options) do |http, body|
        http.response_header.status.should eq(404)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can create a stash (json document)' do
    api_test do
      options = {
        :body => {
          :path => 'tester',
          :content => {
            :key => 'value'
          }
        }
      }
      api_request('/stashes', :post, options) do |http, body|
        http.response_header.status.should eq(201)
        body.should include(:path)
        body[:path].should eq('tester')
        redis.get('stash:tester') do |stash_json|
          stash = Oj.load(stash_json)
          stash.should eq({:key => 'value'})
          async_done
        end
      end
    end
  end

  it 'can not create a stash when missing data' do
    api_test do
      options = {
        :body => {
          :path => 'tester'
        }
      }
      api_request('/stashes', :post, options) do |http, body|
        http.response_header.status.should eq(400)
        body.should be_empty
        redis.exists('stash:tester') do |exists|
          exists.should be_false
          async_done
        end
      end
    end
  end

  it 'can not create a non-json stash' do
    api_test do
      options = {
        :body => {
          :path => 'tester',
          :content => 'value'
        }
      }
      api_request('/stashes', :post, options) do |http, body|
        http.response_header.status.should eq(400)
        body.should be_empty
        redis.exists('stash:tester') do |exists|
          exists.should be_false
          async_done
        end
      end
    end
  end

  it 'can create a stash with id (path)' do
    api_test do
      options = {
        :body => {
          :key => 'value'
        }
      }
      api_request('/stash/tester', :post, options) do |http, body|
        http.response_header.status.should eq(201)
        body.should include(:path)
        redis.get('stash:tester') do |stash_json|
          stash = Oj.load(stash_json)
          stash.should eq({:key => 'value'})
          async_done
        end
      end
    end
  end

  it 'can not create a non-json stash with id' do
    api_test do
      options = {
        :body => 'should fail'
      }
      api_request('/stash/tester', :post, options) do |http, body|
        http.response_header.status.should eq(400)
        body.should be_empty
        redis.exists('stash:tester') do |exists|
          exists.should be_false
          async_done
        end
      end
    end
  end

  it 'can provide a stash' do
    api_test do
      api_request('/stash/test/test') do |http, body|
        http.response_header.status.should eq(200)
        body.should be_kind_of(Hash)
        body[:key].should eq('value')
        async_done
      end
    end
  end

  it 'can not provide a nonexistent stash' do
    api_test do
      api_request('/stash/nonexistent') do |http, body|
        http.response_header.status.should eq(404)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can provide multiple stashes' do
    api_test do
      api_request('/stashes') do |http, body|
        http.response_header.status.should eq(200)
        body.should be_kind_of(Array)
        body[0].should be_kind_of(Hash)
        body[0][:path].should eq('test/test')
        body[0][:content].should eq({:key => 'value'})
        async_done
      end
    end
  end

  it 'can delete a stash' do
    api_test do
      api_request('/stash/test/test', :delete) do |http, body|
        http.response_header.status.should eq(204)
        body.should be_empty
        redis.exists('stash:test/test') do |exists|
          exists.should be_false
          async_done
        end
      end
    end
  end

  it 'can not delete a nonexistent stash' do
    api_test do
      api_request('/stash/nonexistent', :delete) do |http, body|
        http.response_header.status.should eq(404)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can provide a list of aggregates' do
    api_test do
      server = Sensu::Server.new(options)
      server.setup_redis
      server.aggregate_result(result_template)
      timer(1) do
        api_request('/aggregates') do |http, body|
          body.should be_kind_of(Array)
          test_aggregate = Proc.new do |aggregate|
            aggregate[:check] == 'foobar'
          end
          body.should contain(test_aggregate)
          async_done
        end
      end
    end
  end

  it 'can provide an aggregate list' do
    api_test do
      server = Sensu::Server.new(options)
      server.setup_redis
      timestamp = epoch
      3.times do |index|
        result = result_template
        result[:check][:issued] = timestamp + index
        server.aggregate_result(result)
      end
      timer(1) do
        api_request('/aggregates/foobar') do |http, body|
          body.should be_kind_of(Array)
          body.should have(3).items
          body.should include(timestamp)
          api_request('/aggregates/foobar?limit=1') do |http, body|
            body.should have(1).items
            api_request('/aggregates/foobar?limit=1&age=30') do |http, body|
              body.should be_empty
              async_done
            end
          end
        end
      end
    end
  end

  it 'can delete aggregates' do
    api_test do
      server = Sensu::Server.new(options)
      server.setup_redis
      server.aggregate_result(result_template)
      timer(1) do
        api_request('/aggregates/foobar', :delete) do |http, body|
          http.response_header.status.should eq(204)
          body.should be_empty
          redis.sismember('aggregates', 'foobar') do |exists|
            exists.should be_false
            async_done
          end
        end
      end
    end
  end

  it 'can not delete nonexistent aggregates' do
    api_test do
      api_request('/aggregates/nonexistent', :delete) do |http, body|
        http.response_header.status.should eq(404)
        body.should be_empty
        async_done
      end
    end
  end

  it 'can provide a specific aggregate with parameters' do
    api_test do
      server = Sensu::Server.new(options)
      server.setup_redis
      result = result_template
      timestamp = epoch
      result[:timestamp] = timestamp
      server.aggregate_result(result)
      timer(1) do
        parameters = '?results=true&summarize=output'
        api_request('/aggregates/foobar/' + timestamp.to_s + parameters) do |http, body|
          http.response_header.status.should eq(200)
          body.should be_kind_of(Hash)
          body[:ok].should eq(0)
          body[:warning].should eq(1)
          body[:critical].should eq(0)
          body[:unknown].should eq(0)
          body[:total].should eq(1)
          body[:results].should be_kind_of(Array)
          body[:results].should have(1).items
          body[:results][0][:client].should eq('i-424242')
          body[:results][0][:output].should eq('WARNING')
          body[:results][0][:status].should eq(1)
          body[:outputs].should be_kind_of(Hash)
          body[:outputs].should have(1).items
          body[:outputs][:'WARNING'].should eq(1)
          async_done
        end
      end
    end
  end

  it 'can not provide a nonexistent aggregate' do
    api_test do
      api_request('/aggregates/foobar/' + epoch.to_s) do |http, body|
        http.response_header.status.should eq(404)
        body.should be_empty
        async_done
      end
    end
  end

  after(:all) do
    async_wrapper do
      amq.queue('results').purge do
        async_done
      end
    end
  end
end
