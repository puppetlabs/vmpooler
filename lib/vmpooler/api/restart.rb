require 'json'

module Vmpooler
  class API
    class Restart < Sinatra::Base
      helpers do
        include Vmpooler::API::Helpers
      end

      # rubocop:disable Lint/MissingSuper
      def initialize(app, options = {})
        @app = app
        @logger = options[:logger]
      end

      def backend
        config = Vmpooler.config
        redis_host = config[:redis]['server']
        redis_port = config[:redis]['port']
        redis_password = config[:redis]['password']
        Vmpooler.new_redis(redis_host, redis_port, redis_password)
      end

      def need_token!
        validate_token(backend)
      end

      def exit_process
        Thread.new do
          at_exit do
            @logger.log('ignored', 'Restarting VMPooler')
          end
          sleep(5)
          exit!
        end
      end

      get '/restart/?' do
        # token authentication
        need_token!

        # restart operation
        exit_process
        status 200
        JSON.pretty_generate({ 'ok' => true, 'message' => 'Restarting ...' })
      end
    end
  end
end
