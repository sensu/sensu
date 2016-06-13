module Sensu
  module API
    module Routes
      module Stashes
        STASHES_URI = /^\/stashes$/
        STASH_URI = /^\/stash(?:es)?\/(.*)$/

        # POST /stash/:path or /stashes/:path
        def post_stash
          path = parse_uri(STASH_URI).first
          read_data do |data|
            @redis.set("stash:#{path}", Sensu::JSON.dump(data)) do
              @redis.sadd("stashes", path) do
                @response_content = {:path => path}
                created!
              end
            end
          end
        end

        # GET /stash/:path or /stashes/:path
        def get_stash
          path = parse_uri(STASH_URI).first
          @redis.get("stash:#{path}") do |stash_json|
            unless stash_json.nil?
              @response_content = Sensu::JSON.load(stash_json)
              respond
            else
              not_found!
            end
          end
        end

        # DELETE /stash/:path or /stashes/:path
        def delete_stash
          path = parse_uri(STASH_URI).first
          @redis.exists("stash:#{path}") do |stash_exists|
            if stash_exists
              @redis.srem("stashes", path) do
                @redis.del("stash:#{path}") do
                  no_content!
                end
              end
            else
              not_found!
            end
          end
        end

        # GET /stashes
        def get_stashes
          @response_content = []
          @redis.smembers("stashes") do |stashes|
            unless stashes.empty?
              stashes = pagination(stashes)
              stashes.each_with_index do |path, index|
                @redis.get("stash:#{path}") do |stash_json|
                  @redis.ttl("stash:#{path}") do |ttl|
                    unless stash_json.nil?
                      item = {
                        :path => path,
                        :content => Sensu::JSON.load(stash_json),
                        :expire => ttl
                      }
                      @response_content << item
                    else
                      @redis.srem("stashes", path)
                    end
                    if index == stashes.length - 1
                      respond
                    end
                  end
                end
              end
            else
              respond
            end
          end
        end

        # POST /stashes
        def post_stashes
          rules = {
            :path => {:type => String, :nil_ok => false},
            :content => {:type => Hash, :nil_ok => false},
            :expire => {:type => Integer, :nil_ok => true}
          }
          read_data(rules) do |data|
            stash_key = "stash:#{data[:path]}"
            @redis.set(stash_key, Sensu::JSON.dump(data[:content])) do
              @redis.sadd("stashes", data[:path]) do
                @response_content = {:path => data[:path]}
                if data[:expire]
                  @redis.expire(stash_key, data[:expire]) do
                    created!
                  end
                else
                  created!
                end
              end
            end
          end
        end
      end
    end
  end
end
