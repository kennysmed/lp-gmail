# coding: utf-8
gem 'oauth2'
require 'sinatra'

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
end


helpers do
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


get '/return/' do
  return 500, "No access token was returned by Google" if !params[:code]

  access_token_obj = auth_client.auth_code.get_token(params[:code], {
                      :redirect_uri => url("/return/"),
                      :token_method => :post
                    })

  redirect "#{session[:bergcloud_return_url]}?config[access_token]=#{access_token_obj.refresh_token}"
end


get '/edition/' do
  erb :publication
end


get '/sample/' do
  erb :publication
end


post '/validate_config/' do
end

