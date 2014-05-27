gem 'em-redis-unified', '0.5.0'

require 'em-redis'

module Sensu
  class Redis
    def self.connect(options={})
      options ||= Hash.new
      connection = EM::Protocols::Redis.connect(options)
      connection.info do |info|
        if info[:redis_version] < '1.3.14'
          klass = EM::Protocols::Redis::RedisError
          message = 'redis version must be >= 2.0 RC 1'
          connection.error(klass, message)
        end
      end
      connection
    end
  end
end
