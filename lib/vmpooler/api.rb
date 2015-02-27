module Vmpooler
  class API < Sinatra::Base
    def initialize
      # Load the configuration file
      config_file = File.expand_path('vmpooler.yaml')
      $config = YAML.load_file(config_file)

      $config[:uptime] = Time.now

      # Set some defaults
      $config[:redis] ||= {}
      $config[:redis]['server'] ||= 'localhost'

      if $config[:graphite]['server']
        $config[:graphite]['prefix'] ||= 'vmpooler'
      end

      # Connect to Redis
      $redis = Redis.new(host: $config[:redis]['server'])

      super()
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
      erb :dashboard, locals: {
        site_name: $config[:config]['site_name'] || '<b>vmpooler</b>'
      }
    end

    %w( dashboard reroute v1 ).each do |lib|
      begin
        require "api/#{lib}"
      rescue LoadError
        require File.expand_path(File.join(File.dirname(__FILE__), 'api', lib))
      end
    end

    use Vmpooler::API::Dashboard
    use Vmpooler::API::Reroute
    use Vmpooler::API::V1

    Thread.new do
      run!
    end
  end
end
