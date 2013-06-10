# coding: utf-8
require 'sinatra/base'
require 'lpgmail/gmail'
require 'lpgmail/store'


module LpGmail
  class Frontend < Sinatra::Base

    set :sessions, true
    set :public_folder, 'public'
    set :views, settings.root + '/../views'

    gmail = LpGmail::Gmail.new
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

      def gmail_login(refresh_token)
        begin
          gmail.login(refresh_token)
        rescue OAuth2::Error => error
          halt error.code, "Error when trying to log in: #{error_description}"
        rescue Net::IMAP::ResponseError => error
          halt 500, "Error when trying to log in: #{error}"
        rescue => error
          halt 500, "Error when trying to log in: #{error}"
        end
      end

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

      redirect gmail.authorize_url(url('/return/'))
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
        gmail.fetch_token(params[:code], url('/return/'))
      rescue OAuth2::Error => error
        return error.code, "Error when trying to get an access token from Google (1a): #{error_description}"
      rescue => error
        return 500, "Error when trying to get an access token from Google (1b): #{error}"
      end

      # Save this for now, as we'll save it in DB once we've finished.
      session[:refresh_token] = gmail.refresh_token
      # We'll use this in the next stage when checking their email address.
      session[:access_token] = gmail.access_token

      gmail.imap_disconnect

      # Now choose the mailboxes.
      redirect url('/setup/')
    end


    # # The user has authenticated with Google, now we need their Gmail address.
    # # Or, they've filled out form already, but there was an error.
    # get '/setup/email/' do
    #   if session[:form_errors]
    #     @form_errors = Marshal.load(session[:form_errors])
    #     session[:form_errors] = nil
    #   else
    #     @form_errors = {}
    #   end

    #   if session[:email]
    #     @email = session[:email]
    #     session[:email] = nil
    #   end

    #   erb :setup_email, :layout => :layout_setup
    # end


    # # The user has submitted the email address form.
    # post '/setup/email/' do
    #   @form_errors = {}

    #   # Check the presence and validity of the email address.
    #   if !params[:email] || params[:email] == ''
    #     @form_errors['email'] = "Please enter your Gmail address"

    #   elsif !gmail_imap.email_is_valid?(params[:email])
    #     @form_errors['email'] = "This email address doesn't seem to be valid"

    #   elsif !gmail_imap.authentication_is_valid?(params[:email], session[:access_token])
    #     @form_errors['email'] = "We couldn't verify your address with Gmail.<br />Is this the same Gmail address as the Google account you authenticated with?"
    #   end

    #   if @form_errors.length > 0 
    #     # Email address isn't right.
    #     session[:form_errors] = Marshal.dump(@form_errors)
    #     session[:email] = params[:email]
    #     redirect url('/setup/email/')
    #   else
    #     # All good - on to selecting mailboxes.
    #     session[:id] = user_store.store(params[:email], session[:refresh_token])
    #     session[:email] = params[:email]
    #     session[:form_errors] = nil
    #     redirect('/setup/mailboxes/')
    #   end
    # end


    get '/setup/' do
      if session[:form_errors]
        @form_errors = Marshal.load(session[:form_errors])
        session[:form_errors] = nil
      end

      gmail_login(session[:refresh_token])

      @email = gmail.user_data['email']
      @mailboxes = gmail.get_mailboxes

      gmail.imap_disconnect

      erb :setup
    end


    post '/setup/' do
      @form_errors = {}

      gmail_login(session[:refresh_token])

      mailboxes = gmail.get_mailboxes

      # VALIDATE MAILBOX FORM.

      gmail.imap_disconnect

      if @form_errors.length > 0 
        # Something's up. 
        session[:form_errors] = Marshal.dump(@form_errors)
        # STORE FORM SELECTIONS IN SESSION.
        redirect url('/setup/')
      else
        # All good.
        # STORE SELECTED MAILBOX INFO IN OUR REDIS STORE.
        id = user_store.store(session[:refresh_token])
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
        return 500, "No data found for ID '#{id}'"
      end

      gmail_login(user[:refresh_token])

      @user_data = gmail.user_data

      @mail_data = {:inbox => get_mailbox_data(imap, 'INBOX'),
                    :important => get_mailbox_data(imap, '[Gmail]/Important')}

      gmail.imap_disconnect

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

