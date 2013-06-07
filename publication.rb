# coding: utf-8
require 'gmail_xoauth'
require 'oauth2'
require 'redis'
require 'sinatra'
require 'uuid'

enable :sessions

raise 'GOOGLE_CLIENT_ID is not set' if !ENV['GOOGLE_CLIENT_ID']
raise 'GOOGLE_CLIENT_SECRET is not set' if !ENV['GOOGLE_CLIENT_SECRET']


auth_client = OAuth2::Client.new(
  ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET'], {
    :site => 'https://accounts.google.com',
    :authorize_url => '/o/oauth2/auth',
    :token_url => '/o/oauth2/token'
  })


configure do
  if settings.development?
    # So we can see what's going wrong on Heroku.
    set :show_exceptions, true
  end

  if settings.production?
    raise 'REDISCLOUD_URL is not set' if !ENV['REDISCLOUD_URL']
    uri = URI.parse(ENV['REDISCLOUD_URL'])
    REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
  else
    REDIS = Redis.new()
  end
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

    return data
  end


  def new_imap_connection()
    Net::IMAP.new('imap.gmail.com', 993, usessl=true, certs=nil, verify=false)
  end


  # Doesn't need to be super - just check it's probably an address -
  # because we then try to authenticate over IMAP too.
  def email_is_valid(email)
    if email =~ /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
      return true
    else
      return false
    end
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

  begin
    redirect auth_client.auth_code.authorize_url(
      :scope => 'https://mail.google.com/',
      :redirect_uri => url('/return/'),
      :access_type => 'offline',
      :approval_prompt => 'force'
    )
  end
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

  access_token_obj = auth_client.auth_code.get_token(params[:code], {
                      :redirect_uri => url("/return/"),
                      :token_method => :post
                    })

  # We'll want to save this in the database after we have the user's
  # email address.
  session[:refresh_token] = access_token_obj.refresh_token
  # We'll use this in the next stage to check their email address.
  session[:access_token] = access_token_obj.token

  # Now ask for the email address.
  redirect url('/email/')
end


# The user has authenticated with Google, now we also need their Gmail
# address.
# Or, they've filled out the form already, but there was a problem with their
# email address.
get '/email/' do
  if session[:form_error]
    @form_error = session[:form_error]
    session[:form_error] = nil
  end

  if session[:email]
    @email = session[:email]
    session[:email] = nil
  end

  erb :email
end


# The user has submitted the email address form.
post '/email/' do
  error_msg = nil

  # Check the presence and validity of the email address.
  if !params[:email] || params[:email] == ''
    error_msg = "Please enter your Gmail address"

  elsif !email_is_valid(params[:email])
    error_msg = "This email address doesn't seem to be valid"

  else
    begin
      puts "AUTH"
      puts "EMAIL: "+params[:email]
      puts "TOKEN: "+session[:access_token]
      imap = new_imap_connection()
      imap.authenticate('XOAUTH2', params[:email], session[:access_token])
    rescue
      error_msg = "We couldn't verify your address with Gmail.<br />Is this the same Gmail address as the Google account you authenticated with?"
    end

    imap.disconnect unless imap.disconnected?
  end

  if error_msg
    # Email address isn't right.
    session[:form_error] = error_msg
    session[:email] = params[:email]
    redirect url('/email/')
  else
    # All good.
    id = UUID.generate
    REDIS.set("user:#{id}:refresh_token", session[:refresh_token])
    REDIS.set("user:#{id}:email", params[:email])
    session[:access_token] = nil
    session[:refresh_token] = nil
    redirect "#{session[:bergcloud_return_url]}?config[id]=#{id}"
  end
end
  

get '/edition/' do
  id = params[:id]
  refresh_token = REDIS.get("user:#{id}:refresh_token")
  email = REDIS.get("user:#{id}:email")

  puts "EDITION AUTH"
  puts "EMAIL: " + email
  puts "TOKEN: " + refresh_token
  if !refresh_token || !email
    return 500, "No refresh_token or email found for ID '#{id}'"
  end

  begin
    access_token_obj = OAuth2::AccessToken.from_hash(auth_client,
                                      :refresh_token => refresh_token).refresh!
  rescue OAuth2::Error => error
    return 500, "Error when trying to get an access token from Google (1): #{error}"
  rescue => error
    return 500, "Error when trying to get an access token from Google (2): #{error}"
  end

  begin
    imap = new_imap_connection()
    imap.authenticate('XOAUTH2', email, access_token_obj.token)
  rescue => error
    imap.disconnect unless imap.disconnected?
    return 500, "Error when trying to authenticate with Google IMAP: #{error}"
  end

  @email_address = email
  @mail_data = {:inbox => get_mailbox_data(imap, 'INBOX'),
                :important => get_mailbox_data(imap, '[Gmail]/Important')}

  imap.disconnect unless imap.disconnected?

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

