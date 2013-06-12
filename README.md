# Little Printer Gmail publication

In progress.

* https://developers.google.com/gmail/xoauth2_protocol


## Configuration

Settings can be either in environment variables:

    GOOGLE_CLIENT_ID=12345678901.apps.googleusercontent.com
    GOOGLE_CLIENT_SECRET=ABc-1234567890abcdefghij
    REDISCLOUD_URL=redis://rediscloud:1234567890abcdef@pub-redis-12345.eu-west-1-1.2.ec2.garantiadata.com:12345

or in a `config.yml` file in the same directory as `lpgmail.rb` etc:

    google_client_id: 12345678901.apps.googleusercontent.com
    google_client_secret: ABc-1234567890abcdefghij
    rediscloud_url: redis://rediscloud:1234567890abcdef@pub-redis-12345.eu-west-1-1.2.ec2.garantiadata.com:12345

The `REDISCLOUD_URL` setting is optional. If it's missing then Redis will just use the local Redis database.

If both the environment variables and `config.yml` is present, the former is given precedence.


----

BERG Cloud Developer documentation: http://remote.bergcloud.com/developers/
