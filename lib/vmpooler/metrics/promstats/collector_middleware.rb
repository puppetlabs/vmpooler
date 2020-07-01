# frozen_string_literal: true

# This is an adapted Collector module for vmpooler based on the sample implementation
# available in the prometheus client_ruby library
# https://github.com/prometheus/client_ruby/blob/master/lib/prometheus/middleware/collector.rb
#
# The code was also failing Rubocop on PR check, so have addressed all the offenses.
#
# The method strip_hostnames_from_path (originally strip_ids_from_path) has been adapted
# to add a match for hostnames in paths # to replace with a single ":hostname" string to
# avoid # proliferation of stat lines for # each new vm hostname deleted, modified or
# otherwise queried.

require 'benchmark'
require 'prometheus/client'
require 'vmpooler/logger'

module Vmpooler
  class Metrics
    class Promstats
      # CollectorMiddleware is an implementation of Rack Middleware customised
      # for vmpooler use.
      #
      # By default metrics are registered on the global registry. Set the
      # `:registry` option to use a custom registry.
      #
      # By default metrics all have the prefix "http_server". Set to something
      # else if you like.
      #
      # The request counter metric is broken down by code, method and path by
      # default. Set the `:counter_label_builder` option to use a custom label
      # builder.
      #
      # The request duration metric is broken down by method and path by default.
      # Set the `:duration_label_builder` option to use a custom label builder.
      #
      # Label Builder functions will receive a Rack env and a status code, and must
      # return a hash with the labels for that request. They must also accept an empty
      # env, and return a hash with the correct keys. This is necessary to initialize
      # the metrics with the correct set of labels.
      class CollectorMiddleware
        attr_reader :app, :registry

        def initialize(app, options = {})
          @app = app
          @registry = options[:registry] || Prometheus::Client.registry
          @metrics_prefix = options[:metrics_prefix] || 'http_server'

          init_request_metrics
          init_exception_metrics
        end

        def call(env) # :nodoc:
          trace(env) { @app.call(env) }
        end

        protected

        def init_request_metrics
          @requests = @registry.counter(
            :"#{@metrics_prefix}_requests_total",
            docstring:
              'The total number of HTTP requests handled by the Rack application.',
            labels: %i[code method path]
          )
          @durations = @registry.histogram(
            :"#{@metrics_prefix}_request_duration_seconds",
            docstring: 'The HTTP response duration of the Rack application.',
            labels: %i[method path]
          )
        end

        def init_exception_metrics
          @exceptions = @registry.counter(
            :"#{@metrics_prefix}_exceptions_total",
            docstring: 'The total number of exceptions raised by the Rack application.',
            labels: [:exception]
          )
        end

        def trace(env)
          response = nil
          duration = Benchmark.realtime { response = yield }
          record(env, response.first.to_s, duration)
          response
        rescue StandardError => e
          @exceptions.increment(labels: { exception: e.class.name })
          raise
        end

        def record(env, code, duration)
          counter_labels = {
            code: code,
            method: env['REQUEST_METHOD'].downcase,
            path: strip_hostnames_from_path(env['PATH_INFO'])
          }

          duration_labels = {
            method: env['REQUEST_METHOD'].downcase,
            path: strip_hostnames_from_path(env['PATH_INFO'])
          }

          @requests.increment(labels: counter_labels)
          @durations.observe(duration, labels: duration_labels)
        rescue # rubocop:disable Style/RescueStandardError
          nil
        end

        def strip_hostnames_from_path(path)
          # Custom for /vm path - so we just collect aggrate stats for all usage along this one
          # path. Custom counters are then added more specific endpoints in v1.rb
          # Since we aren't parsing UID/GIDs as in the original example, these are removed.
          # Similarly, request IDs are also stripped from the /ondemand path.
          path
            .gsub(%r{/vm/.+$}, '/vm')
            .gsub(%r{/ondemand/.+$}, '/ondemand')
        end
      end
    end
  end
end
