require 'gmail_xoauth'
require 'oauth2'


module LpGmail
  class Gmail

    auth_client = OAuth2::Client.new(
      ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET'], {
        :site => 'https://accounts.google.com',
        :authorize_url => '/o/oauth2/auth',
        :token_url => '/o/oauth2/token'
      }
    )


    # Provides the URL to which we send the user for them to authenticate
    # with Google, and approve access.
    def oauth_authorize_url()
      auth_client.auth_code.authorize_url(
                :scope => 'https://mail.google.com/',
                :redirect_uri => url('/return/'),
                :access_type => 'offline',
                :approval_prompt => 'force'
              )
    end


    # Provides an access_token object after the user has returned from
    # authenticating with Google.
    # code: The code returned in the URL.
    # redirect_uri: The URI on this site that has been set as the Return URI.
    # Returns an access_token object with .token and .refresh_token attributes.
    # Or, if something goes wrong, a string - an error message.
    def oauth_get_token(code, redirect_uri)
      begin
        return auth_client.auth_code.get_token(code, {
                        :redirect_uri => redirect_uri,
                        :token_method => :post
                      })
      rescue OAuth2::Error => error
        return error
      rescue => error
        return error
      end
    end


    # Get a new access_token using the refresh_token that was stored when
    # the user signed up.
    # Returns an access_token object with .token and .refresh_token attributes.
    # Or, if something goes wrong, a string - an error message.
    def oauth_get_token_from_hash(refresh_token)
      begin
        access_token = OAuth2::AccessToken.from_hash(auth_client,
                                    :refresh_token => refresh_token).refresh!
        puts "ACCESS TOKEN: " + access_token
        return access_token
      rescue OAuth2::Error => error
        return error
      rescue => error
        return error
      end
    end


  end
end
