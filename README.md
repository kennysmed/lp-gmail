# Little Printer Gmail Stats publication

A Ruby + Sinatra publication for [Little Printer](http://bergcloud.com/littleprinter) that displays daily charts for the user's Gmail mailboxes.

It asks the subscribing user to authenticate with their Google account, then
pick up to four mailboxes/labels to be monitored. Every day the publication
will show the chosen stats, building up graphs of the most recent 30 days of
data. [See a sample of the publication.](http://remote.bergcloud.com/publications/177)

This publication is an example of:

* A publication that uses the Sinatra modular style.
* Authenticating with Google using OAuth 2.0.
* Authenticating with Gmail's IMAP.
* Fetching data about Gmail mailboxes/labels.
* Providing an extra configuration step to subscribers.
* Drawing charts with [LPChart](https://github.com/bergcloud/lp-chart).


## Set-up

The app has only been run on [Heroku](http://heroku.com/), using the [Redis
Cloud add-on](https://addons.heroku.com/rediscloud). Set up a new App, with
that add-on.

You will need to get a Google API ID and Secret from their [APIs Console](https://code.google.com/apis/console#access):

1. Create a new Project, then click 'API Access' in the left-hand menu.
2. Click the button to create an OAuth 2.0 client ID.
3. In the pop-up panel, the first page isn't too important. For the 'Home page
   URL' you could give the URL of your publication on
   http://remote.bergcloud.com/
4. On the next page, select the 'Web application' type. Click the 'more
   options' link. For 'Authorized Redirect URIs' enter something like
   `http://my-gmail-pub.herokuapp.com/return`, using your Heroku app's domain.
   You can delete the 'Authorized JavaScript Origins'. Submit the form.
5. You'll need the 'Client ID' and the 'Client secret' displayed on the next
   page. 

If you want to run the code in other places, such as a local development
server, you can create further Client IDs within the same Google API project.

The client ID and secret (and the Redis Cloud URL) can be provided as environment variables, which is the way to do it when running on Heroku, for example:

    GOOGLE_CLIENT_ID=12345678901.apps.googleusercontent.com
    GOOGLE_CLIENT_SECRET=ABc-1234567890abcdefghij
    REDISCLOUD_URL=redis://rediscloud:1234567890abcdef@pub-redis-12345.eu-west-1-1.2.ec2.garantiadata.com:12345

Or they can be set in a `config.yml` file in the same directory as `lpgmail.rb` etc:

    google_client_id: 12345678901.apps.googleusercontent.com
    google_client_secret: ABc-1234567890abcdefghij
    rediscloud_url: redis://rediscloud:1234567890abcdef@pub-redis-12345.eu-west-1-1.2.ec2.garantiadata.com:12345

The `REDISCLOUD_URL` setting is optional. If it's missing then Redis will use a local Redis database, assuming it's available.

If both the environment variables and `config.yml` are present, the former are given precedence.



## Further info

Resources that might be useful if developing a publication based on this one:

* [Google's OAuth 2 API documentation](https://developers.google.com/accounts/docs/OAuth2)
* [Google's Gmail XOAUTH2 documentation](https://developers.google.com/gmail/xoauth2_protocol)
* [Gmail_xoauth](https://github.com/nfo/gmail_xoauth) Ruby gem for accessing
  Gmail's IMAP and STMP via OAuth 2.0
* [Documentation for Net::IMAP](http://ruby-doc.org/stdlib-2.0/libdoc/net/imap/rdoc/Net/IMAP.html), the Ruby library
* [LPChart documentation](http://bergcloud.github.io/lp-chart/) for drawing
  charts


----

BERG Cloud Developer documentation: http://remote.bergcloud.com/developers/
