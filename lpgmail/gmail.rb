# coding: utf-8
require 'gmail_xoauth'
require 'oauth2'


module LpGmail
  class Gmail

    attr_reader :user_data

    def initialize(google_client_id, google_client_secret)
      @auth_client = OAuth2::Client.new(
        google_client_id, google_client_secret, {
          :site => 'https://accounts.google.com',
          :authorize_url => '/o/oauth2/auth',
          :token_url => '/o/oauth2/token'
        }
      )

      # We don't set up the connection initially, as we don't necessarily need
      # this on every request.
      @imap_client = nil

      @access_token_obj = nil

      @user_data = {}
    end


  public

    # Get the OAuth2 access token string (required authentication).
    def access_token()
      if @access_token_obj
        @access_token_obj.token
      else
        return nil
      end
    end


    # Get the OAuth2 refresh token string (required authentication).
    def refresh_token()
      if @access_token_obj
        @access_token_obj.refresh_token
      else
        return nil
      end
    end


    # Provides the URL to which we send the user for them to authenticate
    # with Google, and approve access.
    # redirect_uri: The URI on this site that has been set as the Return URI.
    def authorize_url(redirect_uri)
      @auth_client.auth_code.authorize_url(
                # The second scope lets us fetch the user's gmail address.
                :scope => 'https://mail.google.com/ https://www.googleapis.com/auth/userinfo.email',
                :redirect_uri => redirect_uri,
                :access_type => 'offline',
                :approval_prompt => 'force'
              )
    end


    # Sets the access_token object after the user has returned from
    # authenticating with Google.
    # code: The code returned in the URL.
    # redirect_uri: The URI on this site that has been set as the Return URI.
    # Sets @access_token object with .token and .refresh_token attributes.
    def fetch_token(code, redirect_uri)
      @access_token_obj = @auth_client.auth_code.get_token(code, {
                        :redirect_uri => redirect_uri,
                        :token_method => :post
                      })
    end


    # If we have a refresh_token, this will:
    #  * Do the OAuth2 authentication,
    #  * Fetch the user's data (including email address),
    #  * Authenticate with IMAP.
    #
    # Once done we can access gmail.user_data and call gmail.get_mailboxes().
    # 
    # You should probably check for at least OAuth2::Error and
    # Net::IMAP::ResponseError
    # 
    def login(refresh_token)
      fetch_token_from_hash(refresh_token)

      fetch_user_data()

      imap_authenticate()
    end


    def imap_disconnect()
      if @imap_client
        @imap_client.disconnect unless @imap_client.disconnected?
      end
    end


    # Assuming the user is authenticated, get an array of all their mailboxes/
    # labels.
    # Returns an array of Net::IMAP::MailboxList objects.
    # Some examples:
    # #<struct Net::IMAP::MailboxList attr=[:Hasnochildren, :Flagged], delim="/", name="[Gmail]/Starred">
    # #<struct Net::IMAP::MailboxList attr=[:Hasnochildren], delim="/", name="Housekeeping">
    # #<struct Net::IMAP::MailboxList attr=[:Haschildren], delim="/", name="Parent">
    # #<struct Net::IMAP::MailboxList attr=[:Noselect, :Haschildren], delim="/", name="Parent/Folder">
    # #<struct Net::IMAP::MailboxList attr=[:Hasnochildren], delim="/", name="Parent/Folder/Mailbox">
    def get_mailboxes()

      begin
        mblist = @imap_client.list('', '*')
      rescue
        return [] 
      end

      return order_mailboxes(mblist)
    end


  private


    # Get a new access_token using the refresh_token that was stored when
    # the user signed up.
    # Sets up @ccess_token_obj with .token and .refresh_token attributes.
    def fetch_token_from_hash(refresh_token)
      @access_token_obj = OAuth2::AccessToken.from_hash(@auth_client,
                                    :refresh_token => refresh_token).refresh!
    end


    def fetch_user_data()
      @user_data = @access_token_obj.get(
                        'https://www.googleapis.com/oauth2/v1/userinfo').parsed
    end


    def imap_connect()
      @imap_client = Net::IMAP.new('imap.gmail.com', 993,
                                          usessl=true, certs=nil, verify=false)
    end


    # Authenticate a user with IMAP.
    def imap_authenticate()
      imap_connect()
      @imap_client.authenticate('XOAUTH2', @user_data['email'],
                                                      @access_token_obj.token)
    end


    # Put the list of mailboxes into the order we want - the same as in Gmail.
    # mblist is a list of Net::IMAP::MailboxList objects.
    # We return the same, only the order is changed.
    def order_mailboxes(mblist)
      mailboxes = []

      # Most of the mailboxes are in the correct order, but we want to move
      # these ones to the front because they're displayed first in Gmail.
      # So we delete them from mblist and append to mailboxes.
      mailboxes << mblist.delete( mblist.find{ |m| m.name == 'INBOX' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Starred' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Important' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Sent Mail' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Drafts' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/All Mail' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Spam' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Bin' } )

      # Now put the rest of the mailboxes on the end.
      mailboxes.concat mblist

      return mailboxes
    end


    # Check whether an email and an oauth access_token will let us
    # authenticate with Gmail over IMAP.
    # Returns true or false.
    # def imap_authentication_is_valid?(email, access_token)
    #   success = true

    #   begin
    #     imap_authenticate(email, access_token)
    #   rescue
    #     success = false
    #   end

    #   imap_disconnect()

    #   return success 
    # end


  end
end

