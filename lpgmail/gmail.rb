# coding: utf-8
require 'gmail_xoauth'
require 'oauth2'


module LpGmail
  class Gmail

    def initialize
      @auth_client = OAuth2::Client.new(
        ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET'], {
          :site => 'https://accounts.google.com',
          :authorize_url => '/o/oauth2/auth',
          :token_url => '/o/oauth2/token'
        }
      )
    end


    def new_imap_connection()
      Net::IMAP.new('imap.gmail.com', 993, usessl=true, certs=nil, verify=false)
    end


    # Provides the URL to which we send the user for them to authenticate
    # with Google, and approve access.
    # redirect_uri: The URI on this site that has been set as the Return URI.
    def oauth_authorize_url(redirect_uri)
      @auth_client.auth_code.authorize_url(
                :scope => 'https://mail.google.com/',
                :redirect_uri => redirect_uri,
                :access_type => 'offline',
                :approval_prompt => 'force'
              )
    end


    # Provides an access_token object after the user has returned from
    # authenticating with Google.
    # code: The code returned in the URL.
    # redirect_uri: The URI on this site that has been set as the Return URI.
    # Returns an access_token object with .token and .refresh_token attributes.
    def oauth_get_token(code, redirect_uri)
      @auth_client.auth_code.get_token(code, {
                        :redirect_uri => redirect_uri,
                        :token_method => :post
                      })
    end


    # Get a new access_token using the refresh_token that was stored when
    # the user signed up.
    # Returns an access_token object with .token and .refresh_token attributes.
    def oauth_get_token_from_hash(refresh_token)
      OAuth2::AccessToken.from_hash(@auth_client,
                                    :refresh_token => refresh_token).refresh!
    end


    def test_imap_authentication(email, access_token)
      success = true
      imap = new_imap_connection()

      begin
        imap.authenticate('XOAUTH2', email, access_token)
      rescue
        success = false
      end

      if imap
        imap.disconnect unless imap.disconnected?
      end

      return success 
    end
  end
end

