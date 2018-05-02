require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/client/process"

describe "Sensu::Client::HTTPSocket" do
  include Helpers

  before do
    @client = Sensu::Client::Process.new(options)
  end

  it "can provide basic version and transport information" do
    async_wrapper do
      @client.setup_transport do
        @client.setup_http_socket
        timer(1) do
          http_request(3031, "/info") do |http, body|
            expect(http.response_header.status).to eq(200)
            expect(body[:sensu][:version]).to eq(Sensu::VERSION)
            expect(body[:transport][:connected]).to be(true)
            expect(body[:transport][:keepalives][:messages]).to be_kind_of(Integer)
            expect(body[:transport][:keepalives][:consumers]).to be_kind_of(Integer)
            expect(body[:transport][:results][:messages]).to be_kind_of(Integer)
            expect(body[:transport][:results][:consumers]).to be_kind_of(Integer)
            async_done
          end
        end
      end
    end
  end

  it "can accept external check result input" do
    async_wrapper do
      @client.setup_transport do
        @client.setup_http_socket
        result_queue do |payload|
          result = Sensu::JSON.load(payload)
          expect(result[:client]).to eq("i-424242")
          expect(result[:check][:name]).to eq("http")
          async_done
        end
        timer(1) do
          options = {:body => {:name => "http", :output => "http", :status => 1}}
          http_request(3031, "/results", :post, options) do |http, body|
            expect(http.response_header.status).to eq(202)
            expect(body).to eq({:response => "ok"})
          end
        end
      end
    end
  end

  it "can accept multiple external check results input" do
    async_wrapper do
      @client.setup_transport do
        @client.setup_http_socket
        result_queue do |payload|
          result = Sensu::JSON.load(payload)
          expect(result[:client]).to eq("i-424242")
          expect(result[:check][:name]).to eq("http")
          async_done
        end
        timer(1) do
          options = {:body => [{:name => "http", :output => "http", :status => 1},
                               {:name => "http", :output => "http2", :status => 0},
                               {:name => "http", :output => "http3", :status => 2}]}
          http_request(3031, "/results", :post, options)do |http, body|
            len = options[:body].length-1
            expect(http.response_header.status).to eq(202)
            expect(body).to eq({:response => "ok"})
          end
        end
      end
    end
  end

  it "can provide settings" do
    async_wrapper do
      @client.setup_transport do
        @client.setup_http_socket
        timer(1) do
          options = {
            :head => {
              :authorization => [
                "wrong",
                "credentials"
              ]
            }
          }
          http_request(3031, "/settings", :get, options) do |http, body|
            expect(http.response_header.status).to eq(401)
            http_request(3031, "/settings", :get) do |http, body|
              expect(http.response_header.status).to eq(200)
              expect(body).to be_kind_of(Hash)
              expect(body[:api][:password]).to eq("REDACTED")
              http_request(3031, "/settings?redacted=false", :get) do |http, body|
                expect(http.response_header.status).to eq(200)
                expect(body).to be_kind_of(Hash)
                expect(body[:api][:password]).to eq("bar")
                async_done
              end
            end
          end
        end
      end
    end
  end

  it "can protect all endpoints with basic authentication" do
    async_wrapper do
      @client.settings[:client][:http_socket][:protect_all_endpoints] = true
      @client.setup_transport do
        @client.setup_http_socket
        timer(1) do
          options = {
            :head => {
              :content_type => "application/json",
              :authorization => [
                "wrong",
                "credentials"
              ]
            }
          }
          http_request(3031, "/info", :get, options) do |http, body|
            expect(http.response_header.status).to eq(401)
            options[:body] = {:name => "http", :output => "http", :status => 1}
            http_request(3031, "/results", :post, options) do |http, body|
              expect(http.response_header.status).to eq(401)
              options[:head][:authorization] = ["foo", "bar"]
              http_request(3031, "/info", :get, options) do |http, body|
                expect(http.response_header.status).to eq(200)
                http_request(3031, "/results", :post, options) do |http, body|
                  expect(http.response_header.status).to eq(202)
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
