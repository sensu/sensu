require 'em-http-request'

require File.dirname(__FILE__) + '/../lib/sensu/api.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe "Sensu::API" do
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

  it "should be able to run" do
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
end
