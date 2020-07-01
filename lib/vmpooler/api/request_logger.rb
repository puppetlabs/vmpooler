# frozen_string_literal: true

module Vmpooler
  class API
    class RequestLogger
      attr_reader :app

      def initialize(app, options = {})
        @app = app
        @logger = options[:logger]
      end

      def call(env)
        status, headers, body = @app.call(env)
        @logger.log('s', "[ ] API: Method: #{env['REQUEST_METHOD']}, Status: #{status}, Path: #{env['PATH_INFO']}, Body: #{body}")
        [status, headers, body]
      end
    end
  end
end
