require 'em-http-request'

require File.dirname(__FILE__) + '/../lib/sensu/api.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::API' do
  include Helpers

  before do
    async_wrapper do
      client = client_template
      client[:timestamp] = epoch
      redis.flushdb do
        redis.set('client:i-424242', client.to_json) do
          redis.sadd('clients', 'i-424242') do
            redis.hset('events:i-424242', 'test', {
              :output => 'CRITICAL',
              :status => 2,
              :issued => Time.now.to_i,
              :flapping => false,
              :occurrences => 1
            }.to_json) do
              redis.set('stash:test/test', '{"key": "value"}') do
                redis.sadd('stashes', 'test/test') do
                  async_done
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
        body[:health][:redis].should eq('ok')
        body[:health][:rabbitmq].should eq('ok')
        body[:rabbitmq][:keepalives][:messages].should be_kind_of(Integer)
        body[:rabbitmq][:keepalives][:consumers].should be_kind_of(Integer)
        body[:rabbitmq][:results][:messages].should be_kind_of(Integer)
        body[:rabbitmq][:results][:consumers].should be_kind_of(Integer)
        async_done
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
      api_request('/event/i-424242/test', :delete) do |http, body|
        http.response_header.status.should eq(202)
        body.should be_empty
        amq.queue('results').subscribe do |headers, payload|
          result = JSON.parse(payload, :symbolize_names => true)
          result[:client].should eq('i-424242')
          result[:check][:name].should eq('test')
          result[:check][:status].should eq(0)
          async_done
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
      options = {
        :body => {
          :client => 'i-424242',
          :check => 'test'
        }.to_json
      }
      api_request('/resolve', :post, options) do |http, body|
        http.response_header.status.should eq(202)
        body.should be_empty
        amq.queue('results').subscribe do |headers, payload|
          result = JSON.parse(payload, :symbolize_names => true)
          result[:client].should eq('i-424242')
          result[:check][:name].should eq('test')
          result[:check][:status].should eq(0)
          async_done
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
        }.to_json
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
        }.to_json
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

  it 'can delete a client' do
    api_test do
      api_request('/client/i-424242', :delete) do |http, body|
        http.response_header.status.should eq(202)
        body.should be_empty
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

  after(:all) do
    async_wrapper do
      amq.queue('results').purge do
        async_done
      end
    end
  end
end
