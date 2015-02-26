module Vmpooler
  class API
  class Reroute < Sinatra::Base
    api_version = '1'

    get '/status/?' do
      call env.merge("PATH_INFO" => "/api/v#{api_version}/status")
    end

    get '/summary/?' do
      call env.merge("PATH_INFO" => "/api/v#{api_version}/summary")
    end

    get '/vm/?' do
      call env.merge("PATH_INFO" => "/api/v#{api_version}/vm")
    end

    post '/vm/?' do
      call env.merge("PATH_INFO" => "/api/v#{api_version}/vm")
    end

    post '/vm/:template/?' do
      call env.merge("PATH_INFO" => "/api/v#{api_version}/vm/#{params[:template]}")
    end

    get '/vm/:hostname/?' do
      call env.merge("PATH_INFO" => "/api/v#{api_version}/vm/#{params[:hostname]}")
    end

    delete '/vm/:hostname/?' do
      call env.merge("PATH_INFO" => "/api/v#{api_version}/vm/#{params[:hostname]}")
    end

    put '/vm/:hostname/?' do
      call env.merge("PATH_INFO" => "/api/v#{api_version}/vm/#{params[:hostname]}")
    end
  end
  end
end
