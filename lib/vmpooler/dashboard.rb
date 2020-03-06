# frozen_string_literal: true

module Vmpooler
  class Dashboard < Sinatra::Base
    def config
      Vmpooler.config
    end

    get '/dashboard/?' do
      erb :dashboard, locals: {
        site_name: ENV['SITE_NAME'] || config[:config]['site_name'] || '<b>vmpooler</b>'
      }
    end
  end
end
