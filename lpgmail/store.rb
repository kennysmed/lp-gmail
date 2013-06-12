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
      def store(refresh_token, mailboxes)
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


    # Stores up to @days_to_store worth of message counts for a particular
    # user/mailbox/metric combination.
    class Mailbox < RedisBase

      def initialize(redis_url=nil)
        super(redis_url)

        @days_to_store = 30
      end

      # For an array of mailboxes, store the count for each one.
      # id is the unique User ID.
      def store_set(id, mailboxes)
        mailboxes.each do |mb|
          store(id, mb[:name], mb[:metric], mb[:count])
        end
      end

      # Store a single count for a user/mailbox/metric combination.
      # It's added on to the end of the list for that combo, and the oldest
      # value is removed.
      def store(id, mailbox_name, metric, count)
        key = "#{id}:#{mailbox_name}:#{metric}"
        redis.rpush(key, count)
        redis.ltrim(key, 0, @days_to_store-1)
      end

      # Delete a particular combination and its data. 
      def del(id, mailbox_name, metric)
        redis.del("#{id}:#{mailbox_name}:#{metric}")
      end

      # Get the array of daily counts for a user/mailbox/metric combination.
      def get(id, mailbox_name, metric)
        redis.lrange("#{id}:#{mailbox_name}:#{metric}", 0, -1)
      end
    end

  end
end