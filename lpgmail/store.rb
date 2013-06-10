require 'redis'
require 'redis-namespace'
require 'uuid'


module LpGmail
  module Store
    class RedisBase
      attr_accessor :redis

      def initialize
        if ENV['REDISCLOUD_URL']
          uri = URI.parse(ENV['REDISCLOUD_URL'])
          redis = ::Redis.new(:host => uri.host, :port => uri.port,
                                                    :password => uri.password)
        else
          redis = ::Redis.new
        end
        @redis = ::Redis::Namespace.new(:lpgmail, :redis => redis)
      end
    end


    # Keeps track of oauth refresh_tokens for each user.
    class User < RedisBase
      def store(refresh_token)
        id = UUID.generate
        redis.hset(:user, id, Marshal.dump([refresh_token]))
        return id
      end

      def del(id)
        redis.hdel(:user, id)
      end

      def get(id)
        if data = redis.hget(:user, id)
          arr = Marshal.load(data)
          return {
            :refresh_token => arr[1]
          }
        end
      end
    end

  end
end