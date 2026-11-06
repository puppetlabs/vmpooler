# frozen_string_literal: true

module Vmpooler
  class API < Sinatra::Base
    # Load API components
    %w[helpers dashboard v3 request_logger healthcheck].each do |lib|
      require "vmpooler/api/#{lib}"
    end
    # Load dashboard components
    require 'vmpooler/dashboard'

    def self.execute(torun, config, redis, metrics, logger)
      self.settings.set :config, config
      self.settings.set :redis, redis unless redis.nil?
      self.settings.set :metrics, metrics
      self.settings.set :checkoutlock, Mutex.new

      # Deflating in all situations
      # https://www.schneems.com/2017/11/08/80-smaller-rails-footprint-with-rack-deflate/
      use Rack::Deflater

      # not_found clause placed here to fix rspec test issue.
      not_found do
        content_type :json

        result = {
          ok: false
        }

        JSON.pretty_generate(result)
      end

      if metrics.respond_to?(:setup_prometheus_metrics)
        # Prometheus metrics are only setup if actually specified
        # in the config file.
        metrics.setup_prometheus_metrics(torun)

        # Using customised collector that filters out hostnames on API paths
        require 'vmpooler/metrics/promstats/collector_middleware'
        require 'prometheus/middleware/exporter'
        use Vmpooler::Metrics::Promstats::CollectorMiddleware, metrics_prefix: "#{metrics.prometheus_prefix}_http"
        use Prometheus::Middleware::Exporter, path: metrics.prometheus_endpoint
        # Note that a user may want to use this check without prometheus
        # However, prometheus setup includes the web server which is required for this check
        # At this time prometheus is a requirement of using the health check on manager
        use Vmpooler::API::Healthcheck
      end

      if torun.include? :api
        # Enable API request logging only if required
        use Vmpooler::API::RequestLogger, logger: logger if config[:config]['request_logger']

        use Vmpooler::Dashboard
        use Vmpooler::API::Dashboard
        use Vmpooler::API::V3
      end

      # Get thee started O WebServer
      self.run!
    end
  end
end
