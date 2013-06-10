# coding: utf-8
require 'sinatra/base'
require 'lpgmail/gmail'
require 'lpgmail/store'


module LpGmail
  class Frontend < Sinatra::Base

    set :sessions, true
    set :public_folder, 'public'
    set :views, settings.root + '/../views'

    gmail_auth = LpGmail::GmailAuth.new
    gmail_imap = LpGmail::GmailImap.new
    user_store = LpGmail::Store::User.new


    configure do
      if settings.development?
        # So we can see what's going wrong on Heroku.
        set :show_exceptions, true
      end

      # How many mailboxes/labels do we let the user select?
      set :max_mailboxes, 4
    end


    helpers do

      # Fetch data about an individual Gmail mailbox.
      # `mailbox` is the name of the mailbox, eg 'INBOX', '[Gmail]/Important'.
      # Returns a hash of information.
      def get_mailbox_data(imap, mailbox)
        data = {}

        # We could also use 'RECENT', but Gmail's IMAP implementation
        # doesn't support that.
        # https://support.google.com/mail/answer/78761?hl=en
        mailbox_status = imap.status(mailbox, ['MESSAGES', 'UNSEEN'])

        data[:all_count] = mailbox_status['MESSAGES']
        data[:unseen_count] = mailbox_status['UNSEEN']

        begin
          imap.examine(mailbox)
        rescue => error
          halt 500, "Error examining #{mailbox}: #{error}"
        end

        begin
          data[:flagged_count] = imap.search(['FLAGGED']).length
        rescue => error
          halt 500, "Error counting flagged in #{mailbox}: #{error}"
        end

        time_since = Time.now - (86400 * 1)
        begin
          data[:recent_count] = imap.search(['SINCE', time_since]).length
        rescue => error
          halt 500, "Error counting recent in #{mailbox}: #{error}"
        end

        return data
      end


      def format_title()
        "Gmail Little Printer Publication"
      end
    end


    get '/favicon.ico' do
      status 410
    end


    get '/' do
    end


    # The user has just come here from BERG Cloud to authenticate with Google.
    get '/configure/' do
      return 400, 'No return_url parameter was provided' if !params['return_url']

      # Save these for use when the user returns.
      session[:bergcloud_return_url] = params['return_url']
      session[:bergcloud_error_url] = params['error_url']

      redirect gmail_auth.authorize_url(url('/return/'))
    end


    # Return from Google having authenticated (hopefully).
    # We can now get the access_token and refresh_token from Google.
    get '/return/' do
      if !params[:code]
        if sesssion[:bergcloud_error_url]
          redirect session[:bergcloud_error_url]
        else
          return 500, "No access token was returned by Google"
        end
      end

      begin
        access_token_obj = gmail_auth.get_token(params[:code], url('/return/'))
      rescue OAuth2::Error => error
        return error.code, "Error when trying to get an access token from Google (1a): #{error_description}"
      rescue => error
        return 500, "Error when trying to get an access token from Google (1b): #{error}"
      end


      begin
        user_data_response = access_token_obj.get('https://www.googleapis.com/oauth2/v1/userinfo')
      rescue OAuth2::Error => error
        return error.code, "Error when fetching email address (a): #{error_description}"
      rescue => error
        return 500, "Error when fetching email address (b): #{error}"
      end

      puts "USER DATA"
      puts user_data_response.parsed()


      # Save this for now, as we'll save it in DB once we've finished.
      session[:refresh_token] = access_token_obj.refresh_token
      # We'll use this in the next stage when checking their email address.
      session[:access_token] = access_token_obj.token

      # Now ask for the email address.
      redirect url('/setup/email/')
    end


    # The user has authenticated with Google, now we need their Gmail address.
    # Or, they've filled out form already, but there was an error.
    get '/setup/email/' do
      if session[:form_errors]
        @form_errors = Marshal.load(session[:form_errors])
        session[:form_errors] = nil
      else
        @form_errors = {}
      end

      if session[:email]
        @email = session[:email]
        session[:email] = nil
      end

      erb :setup_email, :layout => :layout_setup
    end


    # The user has submitted the email address form.
    post '/setup/email/' do
      @form_errors = {}

      # Check the presence and validity of the email address.
      if !params[:email] || params[:email] == ''
        @form_errors['email'] = "Please enter your Gmail address"

      elsif !gmail_imap.email_is_valid?(params[:email])
        @form_errors['email'] = "This email address doesn't seem to be valid"

      elsif !gmail_imap.authentication_is_valid?(params[:email], session[:access_token])
        @form_errors['email'] = "We couldn't verify your address with Gmail.<br />Is this the same Gmail address as the Google account you authenticated with?"
      end

      if @form_errors.length > 0 
        # Email address isn't right.
        session[:form_errors] = Marshal.dump(@form_errors)
        session[:email] = params[:email]
        redirect url('/setup/email/')
      else
        # All good - on to selecting mailboxes.
        session[:id] = user_store.store(params[:email], session[:refresh_token])
        session[:email] = params[:email]
        session[:form_errors] = nil
        redirect('/setup/mailboxes/')
      end
    end


    get '/setup/mailboxes/' do
      if session[:form_errors]
        @form_errors = Marshal.load(session[:form_errors])
        session[:form_errors] = nil
      end

      if session[:email]
        @email = session[:email]
      end

      @mailboxes = gmail_imap.get_mailboxes()


      erb :setup_mailboxes, :layout => :layout_setup
    end


    post '/setup/mailboxes/' do
      @form_errors = {}

      # VALIDATE MAILBOX FORM.

      if @form_errors.length > 0 
        # Something's up. 
        session[:form_errors] = Marshal.dump(@form_errors)
        # STORE FORM SELECTIONS IN SESSION.
        redirect url('/setup/mailboxes/')
      else
        # All good.
        # STORE SELECTED MAILBOX INFO IN OUR REDIS STORE.
        id = session[:id]
        session[:id] = nil
        session[:email] = nil
        session[:access_token] = nil
        session[:refresh_token] = nil
        session[:form_errors] = nil
        redirect "#{session[:bergcloud_return_url]}?config[id]=#{id}"
      end
    end
      

    get '/edition/' do
      id = params[:id]
      user = user_store.get(id)

      if !user
        return 500, "No refresh_token or email found for ID '#{id}'"
      end

      # Get a new access_token using the refresh_token we stored.
      begin
        access_token_obj = gmail_auth.get_token_from_hash(user[:refresh_token])
      rescue OAuth2::Error => error
        return error.code, "Error when trying to get an access token from Google (2a): #{error_description}"
      rescue => error
        return 500, "Error when trying to get an access token from Google (2b): #{error}"
      end

      begin
        imap = gmail_imap.authenticate(user[:email], access_token_obj.token)
      rescue => error
        return 500, "Error when trying to authenticate with Google IMAP: #{error}"
      end

      @email_address = user[:email]
      @mail_data = {:inbox => get_mailbox_data(imap, 'INBOX'),
                    :important => get_mailbox_data(imap, '[Gmail]/Important')}

      gmail_imap.disconnect

      # etag Digest::MD5.hexdigest(id + Date.today.strftime('%d%m%Y'))
      # Testing, always changing etag:
      etag Digest::MD5.hexdigest(id + Time.now.strftime('%M%H-%d%m%Y'))
      erb :publication
    end


    get '/sample/' do
      etag Digest::MD5.hexdigest('sample' + Date.today.strftime('%d%m%Y'))
      erb :publication
    end


    post '/validate_config/' do
    end

  end
end

