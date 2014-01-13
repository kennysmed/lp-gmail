# coding: utf-8
require 'json'
require 'sinatra/base'
require 'sinatra/config_file'
require 'redis'
require 'connection_pool'
require 'lpgmail/gmail'
require 'lpgmail/store'


module LpGmail
  class Frontend < Sinatra::Base
    register Sinatra::ConfigFile

    set :sessions, true
    set :public_folder, 'public'
    set :views, settings.root + '/../views'

    configure do

      # How many mailboxes/labels do we let the user select?
      set :max_mailboxes, 4

      # The default metrics the user can choose in the form for each mailbox.
      # Mapping the form value => Readable label.
      # To add a new one, add it here, and then add something to get the
      # data in LpGmail::Gmail::get_mailbox_count().
      set :valid_mailbox_metrics, {
        'total' => 'Total',
        'unread' => 'Unread',
        'flagged' => 'Starred',
        'daily' => 'Last 24 hours'
      }

      if settings.development?
        # So we can see what's going wrong on Heroku.
        set :show_exceptions, true
      end

      # Environment variables/config:

      set :redis_url, nil

      config_file './config.yml'

      # Overwrite config.yml settings if there are ENV variables.
      if ENV['GOOGLE_CLIENT_ID'] != nil
        set :google_client_id, ENV['GOOGLE_CLIENT_ID']
        set :google_client_secret, ENV['GOOGLE_CLIENT_SECRET']
      end
      if ENV['REDISCLOUD_URL'] != nil
        set :redis_url, ENV['REDISCLOUD_URL']
      end
    end


    helpers do

      def redis_pool
        @redis_pool ||= ConnectionPool.new(:size => 8, :timeout => 5) do
          if settings.redis_url
            redis_uri = URI.parse(settings.redis_url)
            client = ::Redis.new(:host => redis_uri.host,
                                 :port => redis_uri.port,
                                 :password => redis_uri.password)
          else
            client = ::Redis.new
          end
        end
      end

      def gmail
        @gmail ||= LpGmail::Gmail.new(settings.google_client_id,
                                      settings.google_client_secret)
      end 

      def user_store
        @user_store ||= LpGmail::Store::User.new(redis_pool)
      end

      def mailbox_store
        @mailbox_store ||= LpGmail::Store::Mailbox.new(redis_pool)
      end

      # Does the OAuth and IMAP authentication, after which @gmail can do
      # things like fetch mailbox data.
      def gmail_login(refresh_token)
        begin
          gmail.login(refresh_token)
        rescue OAuth2::Error => error
          if error.code == 'invalid_grant'
            # This error usually means that the user has revoked access to
            # Gmail.
            redirect to(url('/auth-revoked/')), 302
          else
            error_code = 500
            error_msg = "Error when trying to log in (1): #{error.code}"
          end
        rescue Net::IMAP::ResponseError => error
          error_code = 500
          error_msg = "Error when trying to log in (2): #{error}"
        rescue => error
          error_code = 500
          error_msg = "Error when trying to log in (3): #{error}"
        end
        if error_code
          p "ERROR: #{error_code}: #{error_msg}"
          halt error_code, error_msg
        end
      end

      def default_metric()
        settings.valid_mailbox_metrics.keys[0]
      end

      def format_title()
        "Gmail Little Printer Publication"
      end

      # Used in the template for pluralizing words.
      def pluralize(num, word, ext='s')
        if num.to_i == 1
          return num.to_s + ' ' + word
        else
          return num.to_s + ' ' + word + ext
        end
      end

      # Strips the '[GMAIL]/' bit from mailbox names and adds zero-width spaces
      # after remaining slashes.
      # Passed '[GMAIL]/Important' it returns 'Important'.
      # Passed 'Inbox' it returns 'Inbox'.
      # Passed 'Project/Folder/Mailbox' it returns 'Project/ Folder/ Mailbox'.
      def format_mailbox_name(name)
        name = name.sub(%r{^(\[Gmail\]/)?(.*?)$}, "\\2")
        name.gsub(/\//, "/&#8203;")
      end

      # Just takes a YYYYMMDD format date and makes it into YYYY-MM-DD.
      def format_date(date)
        date.to_s[0, 4] + '-' + date.to_s[4, 2] + '-' + date.to_s[6, 2] 
      end

      # Add commas in long numbers.
      def format_number(num)
        num.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
      end

      # In the publication we display some of the metrics differently.
      def format_metric(metric)
        if metric == 'daily'
          "from past 24 hrs"
        elsif metric == 'flagged'
          "starred"
        else
          metric
        end
      end 
    end


    error 400..500 do
      @message = body[0]
      erb :error, :layout => :layout_config
    end


    get '/favicon.ico' do
      status 410
    end


    get '/' do
    end


    get '/tester/:n' do |total|
      if settings.production?
        p "ENV: production"
      elsif settings.development?
        p "ENV: development"
      elsif settings.test?
        p "ENV: test"
      else
        p "ENV: something else"
      end

      for n in (1..total.to_i)
        p '-----------------------------------'
        id = user_store.store("test-token-#{rand(999999)}",
                             [{:name=>'INBOX', :metric=>'total'}])
        user_store.get(id)
        p "User del"
        user_store.del(id)
      end
      p "DONE #{total} time(s)"
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
          p "ERROR: 500: No access token was returned by Google"
          return 500, "No access token was returned by Google"
        end
      end

      begin
        gmail.fetch_token(params[:code], url('/return/'))
      rescue OAuth2::Error => error
        error_code = error.code.to_i
        error_msg = "Error when trying to get an access token from Google (1a): #{error.description}" 
      rescue => error
        error_code = 500
        error_msg = "Error when trying to get an access token from Google (1b): #{error}"
      end
      if error_code
        p "ERROR: #{error_code}: #{error_msg}"
        return error_code, error_msg
      end

      # Save this for now, as we'll save it in DB once we've finished.
      session[:refresh_token] = gmail.refresh_token
      # We'll use this in the next stage when checking their email address.
      session[:access_token] = gmail.access_token

      gmail.imap_disconnect

      # Now choose the mailboxes.
      redirect url('/mailboxes/')
    end


    # User has authenticated, and now they can choose which mailboxes to see.
    # Or, they've already submitted the mailbox form, and there were errors.
    # form_errors will have the error messages
    # form_values will have form values we need to display again.
    get '/mailboxes/' do
      @form_errors = {}
      @form_values = {}
      if session[:form_errors]
        @form_errors = Marshal.load(session[:form_errors])
        session[:form_errors] = nil
        @form_values = Marshal.load(session[:form_values])
        session[:form_values] = nil
      else
        # Set default values.
        for m in 1..settings.max_mailboxes
          @form_values['mailbox-1'] = 'INBOX'
          @form_values["metric-#{m}"] = default_metric()
        end
      end

      # Sets up self.gmail
      gmail_login(session[:refresh_token])

      @email = gmail.user_data['email']
      @mailboxes = gmail.get_mailboxes

      gmail.imap_disconnect

      erb :mailboxes, :layout => :layout_config
    end


    # User has submitted the form choosing their mailboxes.
    # We either save data and return to BERG Cloud, or redirect to the GET
    # version of this page with errors.
    post '/mailboxes/' do
      @form_errors = {}
      @form_values = {}

      gmail_login(session[:refresh_token])

      mailboxes = gmail.get_mailboxes

      # Set the valid mailbox values we allow from the form:
      # We also use settings.valid_mailbox_metrics.
      valid_mailbox_names = []
      mailboxes.each do |mb|
        # Occasionally we get a nil mailbox. Odd.
        unless mb.nil? or mb.attr.include?(:Noselect)
          valid_mailbox_names << mb.name
        end
      end

      # VALIDATE MAILBOX FORM.
      # Valid submitted data will end up in mailbox_selection, which will
      # be something like this:
      # [
      #   {:name=>"INBOX", :metric=>"total"},
      #   {:name=>"[Gmail]/Sent Mail", :metric=>"unread"},
      #   {:name=>"Test parent/Another/Test", :metric=>"daily"}
      # ] 
      mailbox_selection = []
      for m in 1..settings.max_mailboxes
        # Default for each type of form value:
        mailbox_name = ''
        metric = default_metric()
        if params.include?("mailbox-#{m}") && params["mailbox-#{m}"] != ''
          mailbox_name = params["mailbox-#{m}"]
          if valid_mailbox_names.include? mailbox_name
            if params["metric-#{m}"] && settings.valid_mailbox_metrics.has_key?(params["metric-#{m}"])
              metric = params["metric-#{m}"]
            end
            mailbox_selection << {:name => mailbox_name,
                                  :metric => metric}
          else
            @form_errors["mailbox-#{m}"] = "This isn't a valid mailbox name"
          end
        end
        # Save these in case we need to set the form up again with user's choices:
        @form_values["mailbox-#{m}"] = mailbox_name
        @form_values["metric-#{m}"] = metric
      end

      if mailbox_selection.length == 0
        @form_errors["general"] = "Please select at least one mailbox"
      end

      gmail.imap_disconnect

      if @form_errors.length > 0 
        # Something's up. 
        session[:form_errors] = Marshal.dump(@form_errors)
        session[:form_values] = Marshal.dump(@form_values)
        redirect url('/mailboxes/')
      else
        # All good - save the data and go back to BERG Cloud to finish.
        id = user_store.store(session[:refresh_token], mailbox_selection)
        session[:access_token] = nil
        session[:refresh_token] = nil
        session[:form_errors] = nil
        redirect "#{session[:bergcloud_return_url]}?config[id]=#{id}"
      end
    end
      

    get '/edition/' do
      id = params[:id]
      puts "Starting edition for #{id}"

      # Will have :refresh_token and :mailboxes keys.
      user = user_store.get(id)

      if !user
        p "ERROR: 500: No user data found for ID '#{id}'"
        return 500, "No user data found for ID '#{id}'"
      end

      gmail_login(user[:refresh_token])

      # Email, name, etc.
      @gmail_user_data = gmail.user_data

      # Will add today's daily counts to each mailbox/metric pair.
      # Each mailbox will then have :name, :metric and :count.
      @mailboxes = gmail.get_daily_counts(user[:mailboxes])

      # Save today's data in the DB with the existing older data.
      mailbox_store.store_array(id, @mailboxes)

      # Will add the historical data to each mailbox/metric pair.
      # Each array in @mailboxes will have :name, :metric, :count and :history.
      @mailboxes.each_with_index do |mb, i|
        @mailboxes[i][:history] = mailbox_store.get(id, mb[:name], mb[:metric]) 
      end

      gmail.imap_disconnect

      # Some weird thing with yield and scope means we should declare this
      # here, not just within the layout/template.
      @days_of_data = @mailboxes[0][:history].length

      puts "Data about #{@mailboxes.length} mailbox(es) for #{id}"

      etag Digest::MD5.hexdigest(id + Date.today.strftime('%d%m%Y'))
      # Testing, always changing etag:
      #etag Digest::MD5.hexdigest(id + Time.now.strftime('%M%H-%d%m%Y'))
      erb :publication, :layout => :layout_publication
    end


    # A standard sample publication at /sample/
    # Or add a number of days' history to view by doing /sample/1/ or
    # /sample/25/ etc, up to 30.
    get %r{/sample/(\d+/)?} do |days|

      @gmail_user_data = {
        "id"=>"123456789012345678901",
        "email"=>"alex.t.andover@gmail.com",
        "verified_email"=>true,
        "hd"=>"example.com"
      }

      @mailboxes = JSON.parse( IO.read(Dir.pwd + '/public/sample_mailboxes.json') )

      # Turn all the keys (which are strings) into symbols:
      @mailboxes.each_with_index do |mb, i|
        @mailboxes[i].keys.each do |key|
          @mailboxes[i][(key.to_sym rescue key) || key] = @mailboxes[i].delete(key)
        end
        # Trim the historical data if asked:
        if days and days.to_i < 30
          @mailboxes[i][:history] = @mailboxes[i][:history][0...days.to_i]
          @mailboxes[i][:count] = @mailboxes[i][:history].last[1]
        end
      end

      # Some weird thing with yield and scope means we should declare this
      # here, not just within the layout/template.
      @days_of_data = @mailboxes[0][:history].length

      etag Digest::MD5.hexdigest('sample' + Date.today.strftime('%d%m%Y'))
      erb :publication, :layout => :layout_publication
    end


    # The user gets this version of the publication if they've revoked
    # authentication with Gmail. We want to tell them they should unsubscribe.
    get '/auth-revoked/' do
      etag Digest::MD5.hexdigest('auth-revoked' + Date.today.strftime('%d%m%Y'))
      erb :auth_revoked, :layout => :layout_publication
    end

  end
end

