require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/server/tessen"
require "sensu/settings"
require "sensu/logger"
require "sensu/redis"

describe "Sensu::Server::Tessen" do
  include Helpers

  before do
    async_wrapper do
      @tessen = Sensu::Server::Tessen.new(
        :settings => Sensu::Settings.get(options),
        :logger => Sensu::Logger.get(options),
        :redis => redis
      )
      redis.flushdb do
        redis.sadd("clients", "i-424242") do
          redis.sadd("servers", "i-424242") do
            async_done
          end
        end
      end
    end
  end

  it "can determine if its enabled" do
    expect(@tessen.enabled?).to eq(false)
    @tessen.options[:enabled] = true
    expect(@tessen.enabled?).to eq(true)
  end

  it "can run and stop" do
    async_wrapper do
      @tessen.run
      expect(@tessen.timers.size).to eq(1)
      @tessen.stop
      expect(@tessen.timers.size).to eq(0)
      async_done
    end
  end

  it "can determine the sensu install id" do
    async_wrapper do
      @tessen.redis = setup_redis
      @tessen.get_install_id do |install_id_one|
        expect(install_id_one).to be_kind_of(String)
        expect(install_id_one).to_not be_empty
        @tessen.get_install_id do |install_id_two|
          expect(install_id_one).to eq(install_id_two)
          async_done
        end
      end
    end
  end

  it "can determine the client count" do
    async_wrapper do
      @tessen.redis = setup_redis
      @tessen.get_client_count do |client_count|
        expect(client_count).to eq(1)
        async_done
      end
    end
  end

  it "can determine the server count" do
    async_wrapper do
      @tessen.redis = setup_redis
      @tessen.get_server_count do |server_count|
        expect(server_count).to eq(1)
        async_done
      end
    end
  end

  it "can determine the version info" do
    version_info = @tessen.get_version_info
    expect(version_info).to be_kind_of(Array)
    expect(version_info.size).to eq(2)
    type, version = version_info
    expect(type).to eq("core")
    expect(version).to eq(Sensu::VERSION)
  end

  it "can create data" do
    async_wrapper do
      @tessen.redis = setup_redis
      @tessen.create_data do |data|
        expect(data).to be_kind_of(Hash)
        expect(data[:tessen_identity_key]).to be_kind_of(String)
        expect(data[:install]).to be_kind_of(Hash)
        expect(data[:install][:id]).to be_kind_of(String)
        expect(data[:install][:id]).to_not be_empty
        expect(data[:install][:sensu_flavour]).to eq("core")
        expect(data[:install][:sensu_version]).to eq(Sensu::VERSION)
        expect(data[:metrics]).to be_kind_of(Hash)
        expect(data[:metrics][:points]).to be_kind_of(Array)
        expect(data[:metrics][:points].size).to eq(2)
        async_done
      end
    end
  end

  it "can make a tessen call-home service api request" do
    tessen_url = "https://tessen.sensu.io/v1/data"
    stub_request(:post, tessen_url).
      with(:body => "{\"install\":{\"id\":\"foo\"}}").
      to_return(:status => 200)
    async_wrapper do
      @tessen.tessen_api_request({:install => {:id => "foo"}}) do
        assert_requested(:post, tessen_url)
        async_done
      end
    end
  end

  it "can fail to make a tessen call-home service api request" do
    tessen_url = "https://tessen.sensu.io/v1/data"
    stub_request(:post, tessen_url).to_return(:status => 500)
    async_wrapper do
      @tessen.tessen_api_request({:install => {:id => "foo"}}) do
        assert_requested(:post, tessen_url)
        async_done
      end
    end
  end

  it "can send data to the tessen call-home service" do
    tessen_url = "https://tessen.sensu.io/v1/data"
    stub_request(:post, tessen_url).to_return(:status => 200)
    async_wrapper do
      @tessen.redis = setup_redis
      @tessen.send_data do
        assert_requested(:post, tessen_url)
        async_done
      end
    end
  end
end
