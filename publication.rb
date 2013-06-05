# coding: utf-8
require 'sinatra'


configure do
end


helpers do
end


get '/' do
end


get '/edition/' do
  erb :publication
end


get '/configure' do
end


# get '/return/' do
# end


get '/sample/' do
  erb :publication
end


post '/validate_config/' do
end

