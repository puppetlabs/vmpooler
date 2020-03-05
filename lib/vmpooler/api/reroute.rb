# frozen_string_literal: true

module Vmpooler
  class API
    class Reroute < Sinatra::Base
      api_version = '1'

      get '/status/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/status")
      end

      get '/summary/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/summary")
      end

      get '/summary/:route/?:key?/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/summary/#{params[:route]}/#{params[:key]}")
      end

      get '/token/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/token")
      end

      post '/token/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/token")
      end

      get '/token/:token/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/token/#{params[:token]}")
      end

      delete '/token/:token/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/token/#{params[:token]}")
      end

      get '/vm/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm")
      end

      post '/vm/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm")
      end

      post '/vm/:template/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:template]}")
      end

      get '/vm/:hostname/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}")
      end

      delete '/vm/:hostname/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}")
      end

      put '/vm/:hostname/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}")
      end

      post '/vm/:hostname/snapshot/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}/snapshot")
      end

      post '/vm/:hostname/snapshot/:snapshot/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}/snapshot/#{params[:snapshot]}")
      end

      put '/vm/:hostname/disk/:size/?' do
        call env.merge('PATH_INFO' => "/api/v#{api_version}/vm/#{params[:hostname]}/disk/#{params[:size]}")
      end
    end
  end
end
