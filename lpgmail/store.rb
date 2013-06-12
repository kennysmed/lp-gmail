require 'redis'
require 'redis-namespace'
require 'uuid'


module LpGmail
  module Store
    class RedisBase
      attr_accessor :redis

      def initialize(redis_url=nil)
        if redis_url != nil
          uri = URI.parse(redis_url)
          redis = ::Redis.new(:host => uri.host, :port => uri.port,
                                                    :password => uri.password)
        else
          redis = ::Redis.new
        end
        @redis = ::Redis::Namespace.new(:lpgmail, :redis => redis)
      end
    end


    # Keeps track of data about each user.
    # refresh_token is the Google OAuth2 token for re-authenticating the user.
    # mailboxes will be an array something like this:
    # [
    #   {:name=>"INBOX", :metric=>"total"},
    #   {:name=>"[Gmail]/Sent Mail", :metric=>"unread"},
    #   {:name=>"Test parent/Another/Test", :metric=>"daily"}
    # ] 
    class User < RedisBase
      def store(refresh_token)
        id = UUID.generate
        redis.hset(:user, id, Marshal.dump({:refresh_token => refresh_token,
                                            :mailboxes => mailboxes}))
        return id
      end

      def del(id)
        redis.hdel(:user, id)
      end

      def get(id)
        if data = redis.hget(:user, id)
          Marshal.load(data)
        end
      end
    end

  end
end