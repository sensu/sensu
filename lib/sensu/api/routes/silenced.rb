module Sensu
  module API
    module Routes
      module Silenced
        SILENCED_URI = /^\/silenced$/
        SILENCED_SUBSCRIPTION_URI = /^\/silenced\/subscriptions\/([\w\.-]+)$/
        SILENCED_CHECK_URI = /^\/silenced\/checks\/([\w\.-]+)$/
        SILENCED_CLEAR_URI = /^\/silenced\/clear$/

        # POST /silenced
        def post_silenced
          rules = {
            :subscription => {:type => String, :nil_ok => true},
            :check => {:type => String, :nil_ok => true, :regex => /\A[\w\.-]+\z/},
            :expire => {:type => Integer, :nil_ok => true},
            :reason => {:type => String, :nil_ok => true},
            :creator => {:type => String, :nil_ok => true}
          }
          read_data(rules) do |data|
            if data[:subscription] || data[:check]
              subscription = data.fetch(:subscription, "*")
              check = data.fetch(:check, "*")
              silenced_key = "#{subscription}:#{check}"
              silenced_info = {
                :subscription => data[:subscription],
                :check => data[:check],
                :expire => data[:expire],
                :reason => data[:reason],
                :creator => data[:creator]
              }
              puts silenced_info.inspect
              @redis.set(silenced_key, Sensu::JSON.dump(silenced_info)) do
                @redis.sadd("silenced", silenced_key) do
                  if data[:expire]
                    @redis.expire(silenced_key, data[:expire]) do
                      created!
                    end
                  else
                    created!
                  end
                end
              end
            else
              bad_request!
            end
          end
        end

        # GET /silenced
        def get_silenced
          @response_content = []
          @redis.smembers("silenced") do |silenced_keys|
            unless silenced_keys.empty?
              @redis.mget(*silenced_keys) do |silenced|
                silenced_keys.each_with_index do |silenced_key, silenced_index|
                  if silenced[silenced_index]
                    @response_content << Sensu::JSON.load(silenced[silenced_index])
                  else
                    @redis.srem("silenced", silenced_key)
                  end
                end
                respond
              end
            else
              respond
            end
          end
        end

        # GET /silenced/subscriptions/:subscription
        def get_silenced_subscription
          subscription = parse_uri(SILENCED_SUBSCRIPTION_URI).first
          @response_content = []
          @redis.smembers("silenced") do |silenced_keys|
            silenced_keys.select! do |key|
              key =~ /^#{subscription}:/
            end
            unless silenced_keys.empty?
              @redis.mget(*silenced_keys) do |silenced|
                silenced_keys.each_with_index do |silenced_key, silenced_index|
                  if silenced[silenced_index]
                    @response_content << Sensu::JSON.load(silenced[silenced_index])
                  else
                    @redis.srem("silenced", silenced_key)
                  end
                end
                respond
              end
            else
              respond
            end
          end
        end

        # GET /silenced/checks/:check
        def get_silenced_check
          check_name = parse_uri(SILENCED_CHECK_URI).first
          @response_content = []
          @redis.smembers("silenced") do |silenced_keys|
            silenced_keys.select! do |key|
              key =~ /^.*:#{check_name}$/
            end
            unless silenced_keys.empty?
              @redis.mget(*silenced_keys) do |silenced|
                silenced_keys.each_with_index do |silenced_key, silenced_index|
                  if silenced[silenced_index]
                    @response_content << Sensu::JSON.load(silenced[silenced_index])
                  else
                    @redis.srem("silenced", silenced_key)
                  end
                end
                respond
              end
            else
              respond
            end
          end
        end

        # POST /silenced/clear
        def post_silenced_clear
          rules = {
            :subscription => {:type => String, :nil_ok => true},
            :check => {:type => String, :nil_ok => true, :regex => /\A[\w\.-]+\z/}
          }
          read_data(rules) do |data|
            if data[:subscription] || data[:check]
              subscription = data.fetch(:subscription, "*")
              check = data.fetch(:check, "*")
              silenced_key = "#{subscription}:#{check}"
              @redis.srem("silenced", silenced_key) do
                @redis.del(silenced_key) do
                  no_content!
                end
              end
            else
              bad_request!
            end
          end
        end
      end
    end
  end
end
