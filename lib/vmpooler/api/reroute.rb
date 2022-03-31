# frozen_string_literal: true

module Vmpooler
  class API
    class Reroute < Sinatra::Base
      api_version = '1'

      get '/status/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called /status/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/status")
      end

      get '/summary/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called /summary/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/summary")
      end

      get '/summary/:route/?:key?/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called /summary/:route/?:key?/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/summary/#{params[:route]}/#{params[:key]}")
      end

      get '/token/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called /token/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/token")
      end

      post '/token/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called post /token/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/token")
      end

      get '/token/:token/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called /token/:token/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/token/#{params[:token]}")
      end

      delete '/token/:token/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called delete /token/:token/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/token/#{params[:token]}")
      end

      get '/vm/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called /vm? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm")
      end

      post '/vm/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called post /vm? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm")
      end

      post '/vm/:template/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called post /vm/:template/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:template]}")
      end

      get '/vm/:hostname/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called /vm/:hostname/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}")
      end

      delete '/vm/:hostname/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called delete /vm/:hostname/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}")
      end

      put '/vm/:hostname/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called put /vm/:hostname/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}")
      end

      post '/vm/:hostname/snapshot/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called post /vm/:hostname/snapshot/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}/snapshot")
      end

      post '/vm/:hostname/snapshot/:snapshot/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called post /vm/:hostname/snapshot/:snapshot/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}/snapshot/#{params[:snapshot]}")
      end

      put '/vm/:hostname/disk/:size/?' do
        puts "DEPRECATION WARNING a client (#{request.user_agent}) called put /vm/:hostname/disk/:size/? and got redirected to api_version=1, this behavior will change in the next major version, please modify the client to use v2 in advance"
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}/disk/#{params[:size]}")
      end
    end
  end
end
