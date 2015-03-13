gem "em-redis-unified", "0.6.0"

require "em-redis"

module Sensu
  class Redis
    # Connect to Redis and ensure that the Redis version is at least
    # 1.3.14, in order to support certain commands.
    #
    # @param options [Hash]
    # @return [Object] Redis connection object.
    def self.connect(options={})
      options ||= {}
      connection = EM::Protocols::Redis.connect(options)
      connection.info do |info|
        if info[:redis_version] < "1.3.14"
          klass = EM::Protocols::Redis::RedisError
          message = "redis version must be >= 2.0 RC 1"
          connection.error(klass, message)
        end
      end
      connection
    end
  end
end
