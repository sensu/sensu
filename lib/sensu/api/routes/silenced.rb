module Sensu
  module API
    module Routes
      module Silenced
        SILENCED_URI = /^\/silenced$/
        SILENCED_ID_URI = /^\/silenced\/ids\/([\w\.\-\*\:]+)$/
        SILENCED_SUBSCRIPTION_URI = /^\/silenced\/subscriptions\/([\w\.\-:]+)$/
        SILENCED_CHECK_URI = /^\/silenced\/checks\/([\w\.\-]+)$/
        SILENCED_CLEAR_URI = /^\/silenced\/clear$/

        # Fetch silenced registry entries for the provided silenced
        # entry keys.
        #
        # @param silenced_keys [Array]
        # @yield callback [entries] callback/block called after the
        #   silenced registry entries have been fetched.
        def fetch_silenced(silenced_keys=[])
          entries = []
          unless silenced_keys.empty?
            @redis.mget(*silenced_keys) do |silenced|
              silenced_keys.each_with_index do |silenced_key, silenced_index|
                if silenced[silenced_index]
                  silenced_info = Sensu::JSON.load(silenced[silenced_index])
                  @redis.ttl(silenced_key) do |ttl|
                    silenced_info[:expire] = ttl
                    entries << silenced_info
                    if silenced_index == silenced_keys.length - 1
                      yield(entries)
                    end
                  end
                else
                  @redis.srem("silenced", silenced_key)
                  if silenced_index == silenced_keys.length - 1
                    @redis.ping do
                      yield(entries)
                    end
                  end
                end
              end
            end
          else
            yield(entries)
          end
        end

        # POST /silenced
        def post_silenced
          rules = {
            :subscription => {:type => String, :nil_ok => true, :regex => /\A[\w\.\-\:]+\z/},
            :check => {:type => String, :nil_ok => true, :regex => /\A[\w\.-]+\z/},
            :begin => {:type => Integer, :nil_ok => true},
            :expire => {:type => Integer, :nil_ok => true},
            :reason => {:type => String, :nil_ok => true},
            :creator => {:type => String, :nil_ok => true},
            :expire_on_resolve => {:type => [TrueClass, FalseClass], :nil_ok => true}
          }
          read_data(rules) do |data|
            if data[:subscription] || data[:check]
              subscription = data.fetch(:subscription, "*")
              check = data.fetch(:check, "*")
              silenced_id = "#{subscription}:#{check}"
              timestamp = Time.now.to_i
              silenced_info = {
                :id => silenced_id,
                :subscription => data[:subscription],
                :check => data[:check],
                :reason => data[:reason],
                :creator => data[:creator],
                :begin => data[:begin],
                :expire_on_resolve => data.fetch(:expire_on_resolve, false),
                :timestamp => timestamp
              }
              silenced_key = "silence:#{silenced_id}"
              @redis.set(silenced_key, Sensu::JSON.dump(silenced_info)) do
                @redis.sadd("silenced", silenced_key) do
                  if data[:expire]
                    expire = data[:expire]
                    if data[:begin]
                      diff = data[:begin] - timestamp
                      expire += diff if diff > 0
                    end
                    @redis.expire(silenced_key, expire) do
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
          @redis.smembers("silenced") do |silenced_keys|
            silenced_keys = pagination(silenced_keys)
            fetch_silenced(silenced_keys) do |silenced|
              @response_content = silenced
              respond
            end
          end
        end

        # GET /silenced/subscriptions/:subscription
        def get_silenced_subscription
          subscription = parse_uri(SILENCED_SUBSCRIPTION_URI).first
          @redis.smembers("silenced") do |silenced_keys|
            silenced_keys.select! do |key|
              key =~ /^silence:#{subscription}:/
            end
            silenced_keys = pagination(silenced_keys)
            fetch_silenced(silenced_keys) do |silenced|
              @response_content = silenced
              respond
            end
          end
        end

        # GET /silenced/ids/:id
        def get_silenced_id
          id = parse_uri(SILENCED_ID_URI).first
          @redis.smembers("silenced") do |silenced_keys|
            silenced_keys.select! do |key|
              key =~ /#{id.gsub('*', '\*')}$/
            end
            silenced_keys = pagination(silenced_keys)
            fetch_silenced(silenced_keys) do |silenced|
              if silenced.empty?
                not_found!
              else
                @response_content = silenced.last
                respond
              end
            end
          end
        end

        # GET /silenced/checks/:check
        def get_silenced_check
          check_name = parse_uri(SILENCED_CHECK_URI).first
          @redis.smembers("silenced") do |silenced_keys|
            silenced_keys.select! do |key|
              key =~ /.*:#{check_name}$/
            end
            silenced_keys = pagination(silenced_keys)
            fetch_silenced(silenced_keys) do |silenced|
              @response_content = silenced
              respond
            end
          end
        end

        # POST /silenced/clear
        def post_silenced_clear
          rules = {
            :id => {:type => String, :nil_ok => true},
            :subscription => {:type => String, :nil_ok => true},
            :check => {:type => String, :nil_ok => true, :regex => /\A[\w\.-]+\z/}
          }
          read_data(rules) do |data|
            if !data[:id].nil? || (data[:subscription] || data[:check])
              subscription = data.fetch(:subscription, "*")
              check = data.fetch(:check, "*")
              silenced_id = data[:id] || "#{subscription}:#{check}"
              silenced_key = "silence:#{silenced_id}"
              @redis.srem("silenced", silenced_key) do
                @redis.del(silenced_key) do |deleted|
                  deleted ? no_content! : not_found!
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
