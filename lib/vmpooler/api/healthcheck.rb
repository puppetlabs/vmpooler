# frozen_string_literal: true

module Vmpooler
  class API
    class Healthcheck < Sinatra::Base
      get '/healthcheck/?' do
        content_type :json

        status 200
        JSON.pretty_generate({ 'ok' => true })
      end
    end
  end
end
