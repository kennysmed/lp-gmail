# coding: utf-8
require 'gmail_xoauth'
require 'oauth2'


module LpGmail
  class GmailAuth

    attr_reader :user_data

    def initialize
      @client = OAuth2::Client.new(
        ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET'], {
          :site => 'https://accounts.google.com',
          :authorize_url => '/o/oauth2/auth',
          :token_url => '/o/oauth2/token'
        }
      )

      @access_token_obj = nil

      @user_data = {}
    end


    def access_token()
      if @access_token_obj
        @access_token_obj.token
      else
        return nil
      end
    end


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
      @client.auth_code.authorize_url(
                # The second scope lets us fetch the user's gmail address.
                :scope => 'https://mail.google.com/ https://www.googleapis.com/auth/userinfo.email',
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
    def get_token(code, redirect_uri)
      @access_token_obj = @client.auth_code.get_token(code, {
                        :redirect_uri => redirect_uri,
                        :token_method => :post
                      })
    end


    # Get a new access_token using the refresh_token that was stored when
    # the user signed up.
    # Returns an access_token object with .token and .refresh_token attributes.
    def get_token_from_hash(refresh_token)
      @access_token_obj = OAuth2::AccessToken.from_hash(@client,
                                    :refresh_token => refresh_token).refresh!
    end


    def get_user_data()
      @user_data = @access_token_obj.get('https://www.googleapis.com/oauth2/v1/userinfo').parsed
    end
  end


  class GmailImap

    # We don't set up the connection initially, as we don't necessarily need
    # this on every request.
    def initialize
      @client = nil
    end


    def connect()
      @client = Net::IMAP.new('imap.gmail.com', 993, usessl=true, certs=nil, verify=false)
    end


    def disconnect()
      if @client
        @client.disconnect unless @client.disconnected?
      end
    end


    # Authenticate a user with IMAP.
    # email is the user's email address.
    # access_token is the OAuth access_token string.
    def authenticate(email, access_token)
      connect()
      @client.authenticate('XOAUTH2', email, access_token)
    end


    # Doesn't need to be super - just check it's probably an address -
    # because we can also use authentication_is_valid?
    def email_is_valid?(email)
      if email =~ /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
        return true
      else
        return false
      end
    end


    # Check whether an email and an oauth access_token will let us
    # authenticate with Gmail over IMAP.
    # Returns true or false.
    def authentication_is_valid?(email, access_token)
      success = true

      begin
        authenticate(email, access_token)
      rescue
        success = false
      end

      disconnect()

      return success 
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
      mailboxes = []

      begin
        mblist = @client.list('', '*')
      rescue
        return mailboxes
      end

      # Most of the mailboxes are in the correct order, but we want to move
      # these ones to the front because they're displayed first in Gmail.
      # So we delete them from mblist and append to mailboxes.
      mailboxes << mblist.delete( mblist.find{ |m| m.name == 'INBOX' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Starred' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Important' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Sent Mail' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Drafts' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Spam' } )
      mailboxes << mblist.delete( mblist.find{ |m| m.name == '[Gmail]/Bin' } )

      # Now put the rest of the mailboxes on the end.
      mailboxes.concat mblist

      return mailboxes
    end
  end
end

