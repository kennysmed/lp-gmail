require 'date'
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
        p "HGET :user #{id}"
        if data = redis.hget(:user, id)
          p "HGET SUCCESSFUL"
          Marshal.load(data)
        end
      end
    end


    # Stores up to @days_to_store worth of message counts for a particular
    # user/mailbox/metric combination.
    # We don't keep track of the date of each message count - this is quite
    # dumb and just stores a list of figures, one per day.
    class Mailbox < RedisBase

      def initialize(redis_url=nil)
        super(redis_url)
        @redis = Redis::Namespace.new(:mailboxes, :redis => @redis)

        @days_to_store = 30
      end

      # For an array of mailboxes, store the count for each one.
      # id is the unique User ID.
      def store_array(id, mailboxes)
        mailboxes.each do |mb|
          store(id, mb[:name], mb[:metric], mb[:count])
        end
      end

      def make_key(id, mailbox_name, metric)
        return "#{id}:#{mailbox_name}:#{metric}"
      end

      # Store a single count for a user/mailbox/metric combination.
      # It's added on to the end of the list for that combo, and the oldest
      # value is removed.
      def store(id, mailbox_name, metric, count)
        key = make_key(id, mailbox_name, metric)
        field = Date.today().strftime('%Y%m%d')

        redis.hset(key, field, count)

        expire_counts(key)
      end

      # For a particular user/mailbox/metric combination (key),
      # delete any date=>count entries which are older than @days_to_store.
      # (Not sure this is the best way to do this?)
      def expire_counts(key)
        # The oldest day we want to keep, like 20130317
        oldest_date = (Date.today() - @days_to_store - 1).strftime('%Y%m%d').to_i
        fields_to_delete = []

        # Each of the fields is like '20130317'.
        redis.hkeys(key).sort!.each do |field|
          if field.to_i < oldest_date
            fields_to_delete.push(field)
          else
            break
          end
        end

        if fields_to_delete.length > 0
          @redis.hdel('a', fields_to_delete)
        end
      end

      # Delete a particular user/mailbox/metric's data. 
      def del(id, mailbox_name, metric)
        redis.del( make_key(id, mailbox_name, metric) )
      end

      # Get the array of daily counts for a user/mailbox/metric combination.
      # Returns an array of arrays, like:
      # [[20130609, 31], [20130610, 19], ... ]
      def get(id, mailbox_name, metric)
        # Will result in an array of arrays, like:
        # [["20130112", "34"], ["20130509", "31"], ... ]
        p "HGETALL #{id}:#{mailbox_name}:#{metric}"
        arr = redis.hgetall(make_key(id, mailbox_name, metric)).sort
        # Turn all those strings to ints.
        arr.map! { |d| [ d[0].to_i, d[1].to_i ] }
        return arr
      end
    end

  end
end
