module Vmpooler
  class API < Sinatra::Base
    def initialize
      super
    end

    set :environment, :production

    not_found do
      content_type :json

      result = {
        ok: false
      }

      JSON.pretty_generate(result)
    end

    get '/' do
      redirect to('/dashboard/')
    end

    # Load dashboard components
    begin
      require "dashboard"
    rescue LoadError
      require File.expand_path(File.join(File.dirname(__FILE__), 'dashboard'))
    end

    use Vmpooler::Dashboard

    # Load API components
    %w( helpers dashboard reroute v1 ).each do |lib|
      begin
        require "api/#{lib}"
      rescue LoadError
        require File.expand_path(File.join(File.dirname(__FILE__), 'api', lib))
      end
    end

    use Vmpooler::API::Dashboard
    use Vmpooler::API::Reroute
    use Vmpooler::API::V1

    def configure(config, redis, environment = :production)
      self.settings.set :config, config
      self.settings.set :redis, redis
      self.settings.set :environment, environment
    end

    def execute!
      self.settings.run!
    end
  end
end
