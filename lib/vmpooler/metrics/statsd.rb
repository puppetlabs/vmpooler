# frozen_string_literal: true

require 'rubygems' unless defined?(Gem)
require 'statsd'

module Vmpooler
  class Statsd < Metrics
    attr_reader :server, :port, :prefix

    def initialize(params = {})
      raise ArgumentError, "Statsd server is required. Config: #{params.inspect}" if params['server'].nil? || params['server'].empty?

      host    = params['server']
      @port   = params['port'] || 8125
      @prefix = params['prefix'] || 'vmpooler'
      @server = ::Statsd.new(host, @port)
    end

    def increment(label)
      server.increment(prefix + '.' + label)
    rescue StandardError => e
      warn "Failure incrementing #{prefix}.#{label} on statsd server [#{server}:#{port}]: #{e}"
    end

    def gauge(label, value)
      server.gauge(prefix + '.' + label, value)
    rescue StandardError => e
      warn "Failure updating gauge #{prefix}.#{label} on statsd server [#{server}:#{port}]: #{e}"
    end

    def timing(label, duration)
      server.timing(prefix + '.' + label, duration)
    rescue StandardError => e
      warn "Failure updating timing #{prefix}.#{label} on statsd server [#{server}:#{port}]: #{e}"
    end
  end
end
